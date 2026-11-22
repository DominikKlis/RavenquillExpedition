local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local C, QualityColor, ItemName = P.C, P.QualityColor, P.ItemName

local Src = { TTL = 30, cache = {}, at = nil }
UI.Src = Src
C.notLearned = "|cff9d9d9d"
C.notLearnedTag = "|cffff4040"

local SafeCall = GCA.SafeCall
local function ExtraRows(extra, key)
  return type(extra[key]) == "table" and extra[key] or {}
end

local function ZoneOf(area, en)
  local z = area and C_Map and SafeCall(C_Map.GetAreaInfo, area)
  if type(z) == "string" and z ~= "" then return z end
  return en
end

local SIDE = { Alliance = "A", Horde = "H" }
local function PlayerSide()
  return SIDE[SafeCall(UnitFactionGroup, "player") or ""]
end

local function FillVendorCosts(list, extra)
  local vendors = type(extra) == "table" and type(extra.v) == "table" and extra.v or nil
  if not vendors then return end
  for _, s in ipairs(list) do
    if s.kind == "vendor" and not s.cost and s.npc then
      for _, e in ipairs(vendors) do
        if e[1] == s.npc.id then s.cost = tonumber(e[5]) end
      end
    end
  end
end

local function HasNonTrainer(list)
  for _, s in ipairs(list) do
    if s.kind ~= "trainer" then return true end
  end
  return false
end

local function ExtraVendorSource(extra)
  local side = PlayerSide()
  local vs = {}
  for _, e in ipairs(ExtraRows(extra, "v")) do
    if not e[6] or not side or e[6] == side then
      vs[#vs + 1] = { id = e[1], name = e[2], zone = ZoneOf(e[3], e[4]), cost = e[5] }
    end
  end
  if not vs[1] then return nil end
  return { kind = "vendor", npc = vs[1], count = #vs, cost = vs[1].cost, extra = true }
end

local function DropLevel(e)
  if not (e[5] and e[6]) then return nil end
  if e[5] == e[6] then return tostring(e[5]) end
  return e[5] .. "-" .. e[6]
end

local function ExtraDropSource(extra)
  local drops = extra.d
  if not (type(drops) == "table" and drops[1]) then return nil end
  local s = { kind = "drop", count = #drops, npcs = {}, extra = true }
  for i = 1, math.min(#drops, 6) do
    local e = drops[i]
    s.npcs[i] = { id = e[1], name = e[2], zone = ZoneOf(e[3], e[4]), level = DropLevel(e), pct = e[7] }
  end
  s.npc = s.npcs[1]
  return s
end

local function AddExtraSources(list, extra)
  local vendor = ExtraVendorSource(extra)
  if vendor then list[#list + 1] = vendor end
  local drop = ExtraDropSource(extra)
  if drop then list[#list + 1] = drop end
  for _, e in ipairs(ExtraRows(extra, "c")) do
    local name = SafeCall(GetItemInfo, e[1])
    list[#list + 1] = { kind = "container", name = (type(name) == "string" and name ~= "") and name or e[2], extra = true }
  end
end

local function AnyWaypoint(list)
  for _, s in ipairs(list) do
    if s.npc and s.npc.map then return true end
  end
  return nil
end

local function OwnRank(prof)
  local own = GCA:OwnProfessions()
  local mine = type(own) == "table" and own[prof]
  return type(mine) == "table" and tonumber(mine.rank) or nil
end

function Src.Build(prof, spellID, recipe)
  recipe = type(recipe) == "table" and recipe or {}
  local info = { list = {}, coarse = recipe.src or "other", skill = tonumber(recipe.skill) or 0 }
  info.have = OwnRank(prof)
  local RS = ns.RecipeSources
  info.sourced = type(RS) == "table" and RS.Collect(info, prof, spellID) or false
  local list = info.list
  if not info.sourced and info.coarse == "trainer" then list[1] = { kind = "trainer" } end
  local extra = ns.ExtraSources and ns.ExtraSources[spellID]
  FillVendorCosts(list, extra)
  if type(extra) == "table" and not HasNonTrainer(list) then AddExtraSources(list, extra) end
  info.canWaypoint = AnyWaypoint(list)
  return info
end

function Src.Get(prof, spellID, recipe)
  local now = GetTime()
  if not Src.at or now - Src.at > Src.TTL then Src.cache, Src.at = {}, now end
  local key = tostring(prof) .. ":" .. tostring(spellID)
  local v = Src.cache[key]
  if v == nil then
    local res = RavenquillExpedition:Call(Src.Build, prof, spellID, recipe)
    if type(res) == "table" then
      v = res
    else
      local rc = type(recipe) == "table" and recipe or {}
      v = { list = {}, coarse = rc.src or "other", skill = tonumber(rc.skill) or 0, failed = true }
      if v.coarse == "trainer" then v.list[1] = { kind = "trainer" } end
    end
    Src.cache[key] = v
  end
  return v
end
function Src.Reset() Src.cache, Src.at = {}, nil end

function UI.SourceInfo(d, cur)
  if type(d) ~= "table" or d.known or type(d.cand) ~= "table" then return nil end
  local prof = cur and cur.prof or GCA:SelectedProfession()
  return Src.Get(prof, d.cand.spellID, d.cand.recipe)
end

local LINE_OF = {}

function LINE_OF.trainer(s, info)
  local sk = info.skill or 0
  if not (info.have and sk > 0) then return string.format(L.SRC_LINE_TRAINER, sk) end
  if info.have >= sk then return string.format(L.SRC_LINE_TRAINER_OK, sk) end
  return string.format(L.SRC_LINE_TRAINER_HAVE, sk, info.have)
end

function LINE_OF.vendor(s)
  local n = s.npc
  if not n then return L.SRC_LINE_VENDOR_OTHER end
  local t = n.zone and string.format(L.SRC_LINE_VENDOR, n.name, n.zone) or string.format(L.SRC_LINE_VENDOR_NOZONE, n.name)
  if s.favor then t = t .. " · " .. string.format(L.SRC_LINE_FAVOR, s.favor) end
  return t
end

function LINE_OF.quest(s)
  if s.level and s.level > 0 then return string.format(L.SRC_LINE_QUEST_LVL, s.name, s.level) end
  return string.format(L.SRC_LINE_QUEST, s.name)
end

function LINE_OF.drop(s)
  local n = s.npc
  local name, zone = n and n.name or "?", n and n.zone or "?"
  if (s.count or 1) > 1 then return string.format(L.SRC_LINE_DROP_N, name, zone, s.count - 1) end
  return string.format(L.SRC_LINE_DROP, name, zone)
end

function LINE_OF.world(s)
  if s.levels then return string.format(L.SRC_LINE_WORLD_LVL, s.levels[1], s.levels[2]) end
  return L.SRC_LINE_WORLD
end

function LINE_OF.objects(s)
  return string.format(L.SRC_LINE_OBJECTS, s.count or 0)
end

function LINE_OF.container(s)
  return string.format(L.SRC_LINE_CONTAINER, s.name or "?")
end

function Src.LineOf(s, info)
  local line = LINE_OF[s.kind]
  if line then return line(s, info) end
  return L.SRC_LINE_OTHER
end

function Src.Line(info)
  if type(info) ~= "table" then return nil end
  local list = info.list or {}
  local text
  if list[1] then
    text = Src.LineOf(list[1], info)
  else
    text = info.coarse == "pattern" and L.SRC_LINE_PATTERN or L.SRC_LINE_OTHER
  end
  if #list > 1 then text = text .. "  " .. C.muted .. string.format(L.SRC_LINE_MORE, #list - 1) .. "|r" end
  return text
end
function UI.SourceLine(d, cur) return Src.Line(UI.SourceInfo(d, cur)) end

local function PlainMoney(c)
  local g, si, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = string.format(L.MONEY_GOLD, g) end
  if si > 0 then parts[#parts + 1] = string.format(L.MONEY_SILVER, si) end
  if k > 0 then parts[#parts + 1] = string.format(L.MONEY_COPPER, k) end
  return table.concat(parts, " ")
end
Src.PlainMoney = PlainMoney

local function Money(c)
  c = tonumber(c)
  if not c or c <= 0 then return nil end
  local s = SafeCall(GetCoinTextureString, c)
  if type(s) == "string" and s ~= "" then return s end
  return PlainMoney(c)
end
Src.Money = Money

local function Loc(n)
  if not n then return "" end
  if n.map then return string.format("%s %.0f, %.0f", n.zone or "", n.x * 100, n.y * 100) end
  return n.zone or ""
end
Src.Loc = Loc

local TIP_GOLD, TIP_GREY, TIP_WHITE = { 1, 0.82, 0 }, { 0.62, 0.62, 0.62 }, { 0.95, 0.95, 0.95 }
local TIP_OK, TIP_BAD, TIP_HINT = { 0.3, 1, 0.3 }, { 1, 0.35, 0.35 }, { 0.5, 0.8, 1 }
local TIP_INDENT = "     "

local Tip = {}

function Tip.Line(text, rgb, wrap)
  GameTooltip:AddLine(text, rgb[1], rgb[2], rgb[3], wrap)
end

function Tip.Double(l, r, lc, rc)
  lc, rc = lc or TIP_WHITE, rc or TIP_GREY
  GameTooltip:AddDoubleLine(l, r or "", lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
end

function Tip.Npc(n)
  if n then Tip.Double(TIP_INDENT .. n.name, Loc(n), TIP_GREY, TIP_GREY) end
end

function Tip.Header(text)
  GameTooltip:AddLine(" ")
  Tip.Line(text, TIP_GOLD)
end

function Tip.Cheapest(costs, key, cost)
  if (cost or 0) > 0 then costs[key] = math.min(costs[key] or cost, cost) end
end

function Tip.TrainerSkill(info)
  local right = string.format(L.SRC_TIP_SKILL, info.skill or 0)
  if not info.have then return right, TIP_GREY end
  if info.have >= (info.skill or 0) then return right .. " (" .. L.SRC_TIP_REACHED .. ")", TIP_OK end
  return right .. " (" .. string.format(L.SRC_TIP_HAVE, info.have) .. ")", TIP_BAD
end

Tip.KIND = {}

function Tip.KIND.trainer(s, info, icon, costs)
  local right, rc = Tip.TrainerSkill(info)
  Tip.Double(icon .. (L.SRC_KIND_TRAINER:gsub("^%l", string.upper)), right, TIP_WHITE, rc)
  Tip.Npc(s.npc)
  Tip.Cheapest(costs, "trainer", s.cost)
end

function Tip.KIND.vendor(s, info, icon, costs)
  Tip.Double(icon .. (s.npc and string.format(L.SRC_LINE_VENDOR_NOZONE, s.npc.name) or L.SRC_LINE_VENDOR_OTHER), Loc(s.npc))
  if s.favor then GameTooltip:AddLine(TIP_INDENT .. string.format(L.SRC_LINE_FAVOR, s.favor), 0.4, 0.7, 1) end
  if (s.count or 0) > 1 then Tip.Line(TIP_INDENT .. string.format(L.SRC_TIP_VENDORS_MORE, s.count - 1), TIP_GREY) end
  Tip.Cheapest(costs, "vendor", s.cost)
end

function Tip.KIND.quest(s, info, icon)
  Tip.Double(icon .. Src.LineOf(s, info), nil, TIP_GOLD)
  Tip.Npc(s.npc)
end

function Tip.KIND.drop(s, info, icon)
  local npcs = s.npcs or {}
  for i, n in ipairs(npcs) do
    local name = n.name .. (n.level and (" (" .. n.level .. ")") or "")
    Tip.Double((i == 1 and icon or TIP_INDENT) .. string.format(L.SRC_TIP_DROP, name), Loc(n))
  end
  if #npcs == 0 then Tip.Double(icon .. Src.LineOf(s, info)) end
  if (s.count or 0) > #npcs and #npcs > 0 then
    Tip.Line(TIP_INDENT .. string.format(L.SRC_TIP_DROPS_MORE, s.count - #npcs), TIP_GREY)
  end
end

function Tip.KIND.other(s, info, icon)
  Tip.Double(icon .. Src.LineOf(s, info))
end

function Tip.Prices(info, costs)
  local ah = Src.PatternPrice(info)
  if not (costs.vendor or costs.trainer or ah) then return end
  Tip.Header(L.PRICE_HEAD)
  if costs.vendor then Tip.Double(L.PRICE_VENDOR, UI.Coins(costs.vendor), TIP_WHITE, TIP_WHITE) end
  if costs.trainer then Tip.Double(L.PRICE_TRAINER, UI.Coins(costs.trainer), TIP_WHITE, TIP_WHITE) end
  if ah then Tip.Double(L.PRICE_AH, UI.Coins(ah), TIP_WHITE, TIP_WHITE) end
end

function Tip.Requirements(info)
  if info.scroll or info.rep then GameTooltip:AddLine(" ") end
  if info.scroll then Tip.Double(L.SRC_TIP_PATTERN_LABEL, ItemName(info.scroll), TIP_GREY, TIP_WHITE) end
  if info.rep then
    Tip.Line(string.format(L.SRC_TIP_REP, info.rep.standing, info.rep.name), info.rep.met and TIP_OK or TIP_BAD, true)
  end
end

function Tip.WaypointHint(info, hints)
  if not info.canWaypoint then return end
  GameTooltip:AddLine(" ")
  if hints then
    Tip.Line(hints.click, TIP_HINT)
    Tip.Line(hints.right, TIP_HINT)
  else
    Tip.Line(L.SRC_TIP_WAYPOINT, TIP_HINT, true)
  end
end

function Src.AddTooltip(info, hints)
  if type(info) ~= "table" then return end
  Tip.Header(L.SRC_TIP_HEAD)
  local costs = {}
  for _, s in ipairs(info.list or {}) do
    local add = Tip.KIND[s.kind] or Tip.KIND.other
    add(s, info, Src.Icon(s.kind) .. " ", costs)
  end
  if not (info.list and info.list[1]) then
    Tip.Line(info.sourced and L.SRC_TIP_UNKNOWN or Src.Line(info), TIP_GREY)
  end
  Tip.Prices(info, costs)
  Tip.Requirements(info)
  Tip.WaypointHint(info, hints)
end

function Src.SetWaypoint(n)
  if not (type(n) == "table" and n.map and n.x and n.y) then return false end
  local tt = _G["TomTom"]
  local ok = type(tt) == "table" and type(tt.AddWaypoint) == "function"
    and pcall(tt.AddWaypoint, tt, n.map, n.x, n.y, { title = n.name, from = L.WAYPOINT_FROM })
  ok = ok or pcall(function()
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then error("no waypoint API") end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(n.map) then error("map refuses waypoints") end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(n.map, n.x, n.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  end)
  GCA:Print(ok and string.format(L.SRC_WAYPOINT_SET, n.name, Loc(n)) or string.format(L.SRC_WAYPOINT_FAIL, n.name, Loc(n)))
  return ok and true or false
end

function Src.ShowOnMap(n)
  if not (type(n) == "table" and n.map and n.x and n.y) then return false end
  local set = Src.SetWaypoint(n)
  local opened = false
  if type(OpenWorldMap) == "function" then opened = pcall(OpenWorldMap, n.map) end
  if not opened and WorldMapFrame then
    opened = pcall(function()
      if not WorldMapFrame:IsShown() then
        if ShowUIPanel then ShowUIPanel(WorldMapFrame) else WorldMapFrame:Show() end
      end
      if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(n.map) end
    end)
  end
  return set, opened
end

local KIND_WORD = { trainer = "SRC_KIND_TRAINER", vendor = "SRC_KIND_VENDOR", quest = "SRC_KIND_QUEST", drop = "SRC_KIND_DROP" }
function Src.MenuEntries(info)
  local out = {}
  for _, s in ipairs(type(info) == "table" and info.list or {}) do
    local n = s.npc
    if n and n.map and KIND_WORD[s.kind] then
      out[#out + 1] = { label = string.format(L.SRC_MENU_WAYPOINT, n.name, L[KIND_WORD[s.kind]]), waypoint = n,
        fn = function() Src.ShowOnMap(n) end }
    end
  end
  return out
end

function Src.Menu(owner, info, title)
  local entries = Src.MenuEntries(info)
  if #entries == 0 then return false end
  if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
    local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
      if title and root.CreateTitle then root:CreateTitle(title) end
      for _, e in ipairs(entries) do root:CreateButton(e.label, e.fn) end
    end)
    if ok then return true end
  end
  entries[1].fn()
  return true
end

function UI.SourceClick(owner, button, d, cur)
  if button ~= "RightButton" then return false end
  local info = UI.SourceInfo(d, cur)
  if not info then return true end
  Src.Menu(owner, info, d.info and d.info.name)
  return true
end

function UI.NotLearnedTip(owner, d, cur)
  if not d then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local r, g, b = QualityColor(d.info and d.info.quality)
  GameTooltip:SetText(d.info and d.info.name or "?", r, g, b)
  GameTooltip:AddLine(L.NOT_LEARNED, 1, 0.35, 0.35)
  UI.AddCrafterLines(d, cur)
  local info = UI.SourceInfo(d, cur)
  if info then Src.AddTooltip(info, { click = L.TIP_HINT_MAP, right = L.TIP_HINT_MENU }) end
  GameTooltip:Show()
end
Src.KIND_ICON = {
  trainer = "Interface\\GossipFrame\\TrainerGossipIcon",
  vendor = "Interface\\GossipFrame\\VendorGossipIcon",
  quest = "Interface\\GossipFrame\\AvailableQuestIcon",
  drop = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
  world = "Interface\\Icons\\INV_Misc_Map_01",
  objects = "Interface\\Icons\\INV_Box_02",
  container = "Interface\\Icons\\INV_Box_02",
  other ="Interface\\Icons\\INV_Scroll_03",
}
function Src.Icon(kind)
  local path = Src.KIND_ICON[kind] or Src.KIND_ICON.other
  if path:find("\\Icons\\", 1, true) then return "|T" .. path .. ":14:14:0:0:64:64:5:59:5:59|t" end
  return "|T" .. path .. ":14:14|t"
end
function Src.PatternPrice(info)
  local A = GCA.Auction
  if not (type(info) == "table" and info.scroll and A and A.Available()) then return nil end
  local si = GCA:GetInfo(info.scroll)
  if si and si.bind == 1 then return nil end
  return A.AuctionPrice(info.scroll)
end
function UI.SourceBadge(d, cur)
  local info = UI.SourceInfo(d, cur)
  local first = info and info.list and info.list[1]
  local kind = first and first.kind or (info and info.coarse == "pattern" and "other") or nil
  if not info or (not first and not info.scroll) then return nil end
  return Src.Icon(kind) .. " " .. (Src.Line(info) or L.NOT_LEARNED)
end
function UI.NotLearnedClick(owner, button, d, cur)
  local info = d and UI.SourceInfo(d, cur)
  if not info then return end
  if button ~= "RightButton" then
    local wps = {}
    for _, e in ipairs(Src.MenuEntries(info)) do if e.waypoint then wps[#wps + 1] = e end end
    if #wps == 1 then wps[1].fn(); return end
  end
  Src.Menu(owner, info, d.info and d.info.name)
end

P.Src = Src
