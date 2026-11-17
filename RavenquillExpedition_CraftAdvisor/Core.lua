local ADDON, ns = ...
local L = ns.L
local RQ = RavenquillExpedition

local DEFAULTS = { guildOnly = true, showUnlearned = false, lookahead = true, autoTarget = true, hideOffline = true, sync = true,
  survival = 0.5, inspectTalents = false,
  memberView = "sheet",
  autoInspect = true,
  needsOffline = false }

local MIGRATIONS = {
  [1] = function(db)
    db.settings = type(db.settings) == "table" and db.settings or {}
    if db.settings.autoInspect == nil and db.settings.autoTarget == false then db.settings.autoInspect = false end
    if not db.inspectTalentsOffV1 then db.settings.inspectTalents = false; db.inspectTalentsOffV1 = true end
  end,
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

local function Newest(v)
  if type(v) ~= "table" then return 0 end
  return math.max(tonumber(v.time) or 0, tonumber(v.ts) or 0)
end
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

local LOGIN_MIGRATIONS = {
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
  launcherRightClick = true,
})
ns.GCA = GCA
GCA.RQ = RQ
GCA.L, GCA.G, GCA.LGet = ns.L, ns.G, ns.LGet
GCA.DEFAULTS = DEFAULTS

GCA.LOOKAHEAD_LEVELS = 5


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

function GCA:Settings() return self.db and self.db.settings end

function GCA:Diag()
  self.db.diag = type(self.db.diag) == "table" and self.db.diag or {}
  return self.db.diag
end

function GCA:OnLoad()
  local db = self.db
  db.members = db.members or {}
  db.known = db.known or {}
  db.specs = db.specs or {}
  db.specManual = db.specManual or {}
  db.profSel = db.profSel or {}
end

function GCA:OnLogin()
  self.loginTime = GetTime()
  self.playerKey = RQ:PlayerKey()
  local _, class = SafeCall(UnitClass, "player")
  if class and not IsSecret(class) then self.playerClass = class end
  local realm = GetRealmName() or "?"
  self.charKey = (self.playerKey or UnitName("player") or "?") .. "-" .. realm
  C_Timer.After(3, function()
    self:CaptureSelf()
    self:RefreshKnown()
    self:PreloadItems()
    self:RefreshOwnSpec()
  end)
  C_Timer.After(self.PRUNE_DELAY + 1, function() RQ:RequestRoster() end)
  C_Timer.After(self.PROF_TRUST_DELAY + 2, function() self:RefreshKnown() end)
  if self.OnSyncLogin then self:OnSyncLogin() end
end

local events = {}

function events:PLAYER_EQUIPMENT_CHANGED()
  if self.equipTimer then return end
  self.equipTimer = true
  C_Timer.After(1, function() self.equipTimer = nil; self:CaptureSelf() end)
end

function events:PLAYER_LEVEL_UP() C_Timer.After(1, function() self:CaptureSelf(); self:QueueOwnSpecRefresh() end) end

function GCA:QueueOwnSpecRefresh()
  if self.specTimer or not (self.db and self.playerKey) then return end
  self.specTimer = true
  C_Timer.After(1.5, function() self.specTimer = nil; self:RefreshOwnSpec() end)
end
function events:TRAIT_CONFIG_UPDATED() self:QueueOwnSpecRefresh() end
events.TRAIT_CONFIG_LIST_UPDATED = events.TRAIT_CONFIG_UPDATED
events.PLAYER_TALENT_UPDATE = events.TRAIT_CONFIG_UPDATED
events.CHARACTER_POINTS_CHANGED = events.TRAIT_CONFIG_UPDATED
events.SPELLS_CHANGED = events.TRAIT_CONFIG_UPDATED

function events:INSPECT_READY(guid) self:OnInspectReady(guid) end

function events:GUILD_ROSTER_UPDATE()
  RQ:Call(self.PruneStale, self)
  self:Invalidate()
end

function events:GET_ITEM_INFO_RECEIVED(itemID, success)
  if IsSecret(itemID) or IsSecret(success) then return end
  local st = itemID and self.loadState[itemID]
  if not st then return end
  if success == false then st.failed = true return end
  if st.failed then self.sugCache = {} end
  self:Invalidate()
end

function events:TRADE_SKILL_SHOW()
  C_Timer.After(0.5, function() self:ScanTradeSkill() end)
end
events.TRADE_SKILL_LIST_UPDATE = events.TRADE_SKILL_SHOW
events.TRADE_SKILL_DATA_SOURCE_CHANGED = events.TRADE_SKILL_SHOW

function events:NEW_RECIPE_LEARNED(recipeID)
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

function events:SKILL_LINES_CHANGED()
  if self.skillTimer or not self.charKey then return end
  self.skillTimer = true
  C_Timer.After(1, function() self.skillTimer = nil; self:RefreshKnown(); self:Invalidate() end)
end

function events:PLAYER_TARGET_CHANGED()
  local s = self:Settings()
  if not (s and s.autoInspect) or InCombatLockdown() then return end
  if not SafeCall(UnitIsPlayer, "target") or SafeCall(UnitIsUnit, "target", "player") then return end
  if not self:IsGuildmate("target") or not SafeCall(CanInspect, "target") then return end
  self:QueueInspect("target", false)
end

function events:GROUP_ROSTER_UPDATE()
  if self.groupTimer or not (self.db and self.db.settings.autoInspect) then return end
  self.groupTimer = true
  C_Timer.After(self.AUTO_GROUP_DELAY, function() self.groupTimer = nil; self:AutoScanGroup() end)
end
function events:UPDATE_MOUSEOVER_UNIT() self:AutoMouseover() end
function events:PLAYER_REGEN_ENABLED()
  if self.autoGroupPending then self:AutoScanGroup() end
  self:ProcessQueue()
  if self.OnSyncRegen then self:OnSyncRegen() end
end
function events:PLAYER_ENTERING_WORLD()
  if self.OnSyncEnteringWorld then self:OnSyncEnteringWorld() end
end

for event, handler in pairs(events) do GCA:RegisterEvent(event, handler) end

