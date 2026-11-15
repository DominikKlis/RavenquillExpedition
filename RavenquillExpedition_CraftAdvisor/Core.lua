-- Guild Craft Advisor: records guildmates' gear when you inspect them and
-- suggests crafts (Leatherworking, Blacksmithing, Tailoring, Engineering, Enchanting) and enchants that would be upgrades.
-- The craft advisor is the suite module "Craft" (core API 2): SavedVariables, migrations, events, options, names,
-- roster and guild sync come from the Ravenquill Expedition core (docs/module-api.md).
-- This file registers the module and keeps the lifecycle and events; the features are in Core/*.lua (loaded after
-- it, see the .toc), which share their file-local helpers through GCA.priv.
local ADDON, ns = ...
local L = ns.L
local RQ = RavenquillExpedition

local DEFAULTS = { guildOnly = true, showUnlearned = false, lookahead = true, autoTarget = true, hideOffline = true, sync = true,
  survival = 0.5, inspectTalents = false, -- inspected talents: off until verified in game
  memberView = "sheet", -- K4: member view variant "sheet" (character sheet) or "list" (cards)
  autoInspect = true,   -- K5: read gear automatically (target, group, mouseover); replaces autoTarget's toggle
  needsOffline = false } -- K5: guild needs include offline members

-- Numbered SavedVariables migrations (run once each, in order, by the core). Each one also checks the flag the
-- addon used before the core counted versions, so nothing runs twice; the flags stay (older versions read them).
local MIGRATIONS = {
  -- K5: "Auto-inspect target" became "Read gear automatically": whoever had turned the old toggle off keeps it off;
  -- 0.3.0 dev builds defaulted inspectTalents to true: reset once (nobody had turned it on by hand yet)
  [1] = function(db)
    db.settings = type(db.settings) == "table" and db.settings or {}
    if db.settings.autoInspect == nil and db.settings.autoTarget == false then db.settings.autoInspect = false end
    if not db.inspectTalentsOffV1 then db.settings.inspectTalents = false; db.inspectTalentsOffV1 = true end
  end,
  -- v0.1 stored Forever names as "First-Surname"; the roster uses "First<sep>Surname" (the newer record wins)
  [2] = function(db)
    if not RQ.IS_FOREVER or db.keysV2 then return end
    db.members = db.members or {}
    local sep, moved = RQ.SurnameSeparator(), {}
    for key, m in pairs(db.members) do
      local first, last = key:match("^([^%-]+)%-(.+)$")
      if first then moved[first .. sep .. last] = m; db.members[key] = nil end
    end
    for key, m in pairs(moved) do
      local cur = db.members[key]
      if not cur or (m.time or 0) > (cur.time or 0) then db.members[key] = m end
    end
    db.keysV2 = true
  end,
  -- diagnostics live under db.diag (made when first needed); the dev probe's saved frame dumps are gone with it
  [3] = function(db)
    for _, k in ipairs({ "diagRosterName", "diagSender", "knownDiag", "lastError" }) do
      if db[k] ~= nil then
        db.diag = type(db.diag) == "table" and db.diag or {}
        if db.diag[k] == nil then db.diag[k] = db[k] end
        db[k] = nil
      end
    end
    db.probe = nil
  end,
}

-- Stamp of a stored entry for "the newer one wins" (gear: time / ts, specs: ts).
local function Newest(v)
  if type(v) ~= "table" then return 0 end
  return math.max(tonumber(v.time) or 0, tonumber(v.ts) or 0)
end
-- Moves every key of t that carries our own "-Realm" to its plain key; on a collision the newer entry stays.
local function RekeyWithoutRealm(t)
  if type(t) ~= "table" then return end
  local moved = {}
  for key, v in pairs(t) do
    local plain = type(key) == "string" and RQ:StripRealm(key)
    if plain then moved[plain] = v; t[key] = nil end
  end
  for key, v in pairs(moved) do
    if t[key] == nil or Newest(v) > Newest(t[key]) then t[key] = v end
  end
end

-- Migrations that need the player and realm (PLAYER_LOGIN).
local LOGIN_MIGRATIONS = {
  -- v0.1 kept known recipes under "First-Realm"; the character key includes the surname since
  [1] = function(db)
    db.known = db.known or {}
    local realm = RQ.Plain(RQ.SafeCall(GetRealmName), "string") or "?"
    local first = RQ.Plain(RQ.SafeCall(UnitName, "player"), "string") or "?"
    local charKey, oldKey = (RQ:PlayerKey() or first) .. "-" .. realm, first .. "-" .. realm
    if oldKey ~= charKey and db.known[oldKey] and not db.known[charKey] then
      db.known[charKey] = db.known[oldKey]
      db.known[oldKey] = nil
    end
  end,
  -- the core's names drop our own realm ("Name-Realm" -> "Name"): member keys stored with it move once
  [2] = function(db)
    RekeyWithoutRealm(db.members)
    RekeyWithoutRealm(db.specs)
    RekeyWithoutRealm(db.specManual)
    for _, byMember in pairs(type(db.crafted) == "table" and db.crafted or {}) do RekeyWithoutRealm(byMember) end
  end,
}

local GCA = RQ:NewModule("Craft", {
  addon = ADDON, api = 2, slash = "craft", title = L.ADDON_TITLE, icon = "Interface\\Icons\\Trade_LeatherWorking",
  sv = "RavenquillExpeditionCraftDB", dbVersion = 3, defaults = DEFAULTS, migrations = MIGRATIONS,
  loginMigrations = LOGIN_MIGRATIONS,
})
ns.GCA = GCA
GCA.priv = {} -- file-local helpers the Core files share (Core.lua and Core/*.lua, in .toc order)
GCA.RQ = RQ
GCA.L, GCA.G, GCA.LGet = ns.L, ns.G, ns.LGet -- locale (Locales\*.lua)
GCA.DEFAULTS = DEFAULTS

GCA.LOOKAHEAD_LEVELS = 5

---------------------------------------------------------------------------
-- Helpers (the core's; SafeCall only probes client APIs)
---------------------------------------------------------------------------
local function Print(...) GCA:Print(...) end

local IsSecret, SafeCall = RQ.IsSecret, RQ.SafeCall
GCA.IsSecret, GCA.SafeCall = IsSecret, SafeCall

local ItemAPI = {
  Info     = (C_Item and C_Item.GetItemInfo) or GetItemInfo,
  Instant  = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant,
  Request  = C_Item and C_Item.RequestLoadItemDataByID,
  Stats    = (C_Item and C_Item.GetItemStats) or GetItemStats,
  NameByID = C_Item and C_Item.GetItemNameByID,
  Count    = (C_Item and C_Item.GetItemCount) or GetItemCount,
}
GCA.ItemAPI = ItemAPI

local function ItemIDFrom(item)
  if type(item) == "number" then return item end
  if type(item) == "string" then return tonumber(item:match("item:(%d+)")) end
end
GCA.ItemIDFrom = ItemIDFrom

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
-- equipLoc -> inventory slots it can go into (relics and weapons too)
GCA.SLOTS_FOR = {
  INVTYPE_RELIC = { 18 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_2HWEAPON = { 16 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
}

---------------------------------------------------------------------------
-- Refresh plumbing
---------------------------------------------------------------------------
function GCA:Invalidate()
  if self.refreshPending then return end
  self.refreshPending = true
  C_Timer.After(0.25, function()
    self.refreshPending = false
    if self.UI and self.UI.Refresh then self.UI:Refresh() end
  end)
end

function GCA:PreloadItems()
  for _, cand in ipairs(self:GetCandidates()) do self:GetInfo(cand.itemID) end
end

---------------------------------------------------------------------------
-- Lifecycle (the core calls OnLoad at our ADDON_LOADED after the migrations and defaults, OnLogin at PLAYER_LOGIN
-- after the login migrations) and events (mod:RegisterEvent: every handler runs under RQ:Call)
---------------------------------------------------------------------------
-- db.diag: diagnostics kept in SavedVariables (known-recipe snapshots, the last UI error)
function GCA:Diag()
  self.db.diag = type(self.db.diag) == "table" and self.db.diag or {}
  return self.db.diag
end

function GCA:OnLoad()
  local db = self.db
  db.members = db.members or {}
  db.known = db.known or {}
  db.specs = db.specs or {}           -- [key] = { class, spec | tree, src = "sync"|"inspect", ts }
  db.specManual = db.specManual or {} -- [key] = { class, spec }: manual pick, wins (F4)
  db.profSel = db.profSel or {}       -- [charKey] = selected profession key (G3)
end

function GCA:OnLogin()
  self.loginTime = GetTime()
  self.playerKey = RQ:PlayerKey()
  local _, class = SafeCall(UnitClass, "player")
  if class and not IsSecret(class) then self.playerClass = class end
  -- per-character key: first name alone isn't unique on Forever, so it includes the surname
  local realm = GetRealmName() or "?"
  self.charKey = (self.playerKey or UnitName("player") or "?") .. "-" .. realm
  self.itemToSpell = self:ItemToSpell(self:SelectedProfession())
  C_Timer.After(3, function()
    self:CaptureSelf()
    self:RefreshKnown()
    self:PreloadItems()
    self:RefreshOwnSpec()
  end)
  -- ask for a fresh roster once pruning is allowed (GUILD_ROSTER_UPDATE then prunes)
  C_Timer.After(self.PRUNE_DELAY + 1, function() RQ:RequestRoster() end)
  -- an empty GetProfessions answer is only trusted PROF_TRUST_DELAY s after login: look again then
  C_Timer.After(self.PROF_TRUST_DELAY + 2, function() self:RefreshKnown(); RQ:Call(self.KnownDiag, self, "login") end)
  if self.OnSyncLogin then self:OnSyncLogin() end
end

local events = {}

function events:PLAYER_EQUIPMENT_CHANGED()
  if self.equipTimer then return end
  self.equipTimer = true
  C_Timer.After(1, function() self.equipTimer = nil; self:CaptureSelf() end)
end

function events:PLAYER_LEVEL_UP() C_Timer.After(1, function() self:CaptureSelf(); self:QueueOwnSpecRefresh() end) end

-- own talents changed (names differ between client generations; unknown events are skipped by pcall)
function GCA:QueueOwnSpecRefresh()
  if self.specTimer or not (self.db and self.playerKey) then return end
  self.specTimer = true
  C_Timer.After(1.5, function() self.specTimer = nil; self:RefreshOwnSpec() end)
end
function events:TRAIT_CONFIG_UPDATED() self:QueueOwnSpecRefresh() end
events.TRAIT_CONFIG_LIST_UPDATED = events.TRAIT_CONFIG_UPDATED
events.PLAYER_TALENT_UPDATE = events.TRAIT_CONFIG_UPDATED
events.CHARACTER_POINTS_CHANGED = events.TRAIT_CONFIG_UPDATED
events.SPELLS_CHANGED = events.TRAIT_CONFIG_UPDATED -- Cat Form learned

function events:INSPECT_READY(guid) self:OnInspectReady(guid) end

-- the core reads the roster at the same event (its frame registered first, so the roster is fresh here)
function events:GUILD_ROSTER_UPDATE()
  RQ:Call(self.PruneStale, self) -- no-op until the roster is trustworthy, then once per session
  self:Invalidate()
end

-- Only items we are waiting for; a failed item that arrives after all drops the suggestion cache (its slot was
-- treated as unknown). success == false: the item doesn't exist -> give up on it, no refresh.
function events:GET_ITEM_INFO_RECEIVED(itemID, success)
  if IsSecret(itemID) or IsSecret(success) then return end
  local st = itemID and self.loadState[itemID]
  if not st then return end
  if success == false then st.failed = true return end
  if st.failed then self.sugCache = {} end
  self:Invalidate()
end

function events:TRADE_SKILL_SHOW()
  C_Timer.After(0.5, function()
    RQ:Call(self.KnownDiag, self, "window") -- before the scan may replace the saved set
    self:ScanTradeSkill()
  end)
end
events.TRADE_SKILL_LIST_UPDATE = events.TRADE_SKILL_SHOW
events.TRADE_SKILL_DATA_SOURCE_CHANGED = events.TRADE_SKILL_SHOW

function events:NEW_RECIPE_LEARNED(recipeID)
  -- the event names the recipe: mark it directly (the spell APIs are not trusted once the window answered)
  if type(recipeID) == "number" and not IsSecret(recipeID) and self.db and self.charKey then
    local store = self:KnownStore()
    for _, p in ipairs(self.PROFESSIONS) do
      if self:KnowableSpells(p.key)[recipeID] then
        store[p.key] = store[p.key] or {}
        store[p.key][recipeID] = true
      end
    end
  end
  C_Timer.After(0.5, function() self:RefreshKnown() end)
end
function events:LEARNED_SPELL_IN_TAB() C_Timer.After(0.5, function() self:RefreshKnown() end) end

-- Diagnostic (temporary): what each "known" source says for recipes that any source calls known.
-- Saved to db.diag.knownDiag so it can be read offline after a /reload. "ips/isk/tsl/saved" = IsPlayerSpell,
-- C_SpellBook.IsSpellKnown, C_TradeSkillUI learned (only while a profession window is open), saved mark.
function GCA:KnownDiag(tag)
  if not (self.db and self.charKey) then return end
  local store = self:KnownStore()
  local out = { when = date and date("%Y-%m-%d %H:%M:%S"), tag = tag }
  local api = C_TradeSkillUI
  for _, p in ipairs(self.PROFESSIONS) do
    local rows = {}
    for id in pairs(self:KnowableSpells(p.key)) do
      local ips = IsPlayerSpell and SafeCall(IsPlayerSpell, id)
      local isk = C_SpellBook and C_SpellBook.IsSpellKnown and SafeCall(C_SpellBook.IsSpellKnown, id)
      local info = api and api.GetRecipeInfo and SafeCall(api.GetRecipeInfo, id)
      local tsl = type(info) == "table" and info.learned
      local saved = store[p.key] and store[p.key][id]
      local function b(v) if IsSecret(v) then return "S" end return v and "1" or (v == false and "0" or "-") end
      if (ips and not IsSecret(ips)) or (isk and not IsSecret(isk)) or (tsl and not IsSecret(tsl)) or saved then
        rows[id] = b(ips) .. b(isk) .. b(tsl) .. b(saved)
      end
    end
    if next(rows) then out[p.key] = rows end
  end
  local diag = self:Diag()
  diag.knownDiag = diag.knownDiag or {}
  diag.knownDiag[tag or "login"] = out
end
-- a profession learned or dropped: re-read professions, clear dropped ones, follow the default selection
function events:SKILL_LINES_CHANGED()
  if self.skillTimer or not self.charKey then return end
  self.skillTimer = true
  C_Timer.After(1, function() self.skillTimer = nil; self:RefreshKnown(); self:Invalidate() end)
end

function events:PLAYER_TARGET_CHANGED()
  local s = self.db and self.db.settings
  if not (s and s.autoInspect) or InCombatLockdown() then return end
  if not SafeCall(UnitIsPlayer, "target") or SafeCall(UnitIsUnit, "target", "player") then return end
  if not self:IsGuildmate("target") or not SafeCall(CanInspect, "target") then return end
  self:QueueInspect("target", false)
end

-- K5: automatic reading of group members (debounced: the event fires in bursts) and of guildies under the mouse
function events:GROUP_ROSTER_UPDATE()
  if self.groupTimer or not (self.db and self.db.settings.autoInspect) then return end
  self.groupTimer = true
  C_Timer.After(self.AUTO_GROUP_DELAY, function() self.groupTimer = nil; self:AutoScanGroup() end)
end
function events:UPDATE_MOUSEOVER_UNIT() self:AutoMouseover() end
-- combat over: a group scan asked for during combat runs now, a waiting queue resumes at once
function events:PLAYER_REGEN_ENABLED()
  if self.autoGroupPending then self:AutoScanGroup() end
  self:ProcessQueue()
  if self.OnSyncRegen then self:OnSyncRegen() end
end
-- Sync.lua: own gear owed after leaving an instance
function events:PLAYER_ENTERING_WORLD()
  if self.OnSyncEnteringWorld then self:OnSyncEnteringWorld() end
end

-- one handler per event; an event this client doesn't know is skipped (mod:RegisterEvent returns false)
for event, handler in pairs(events) do GCA:RegisterEvent(event, handler) end

-- shared with the files loaded after this one (GCA.priv)
GCA.priv.Print = Print
GCA.priv.IsSecret = IsSecret
GCA.priv.SafeCall = SafeCall
GCA.priv.ItemAPI = ItemAPI
GCA.priv.ItemIDFrom = ItemIDFrom
