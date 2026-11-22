local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain
local L = GS.OverviewL
local Text = ns.Text

local WIDE_CARD = "Profession-overview-Card"
local SIZE = { edge = 24, header = 62, footer = 62, pad = 20, top = 14 }
local NOW_CARD = { height = 48, gap = 8, icon = 32, inset = 10, button = 104 }
local NOW_MAX = { withGoal = 5, alone = 6 }

local function BuildHeader(home)
  local card = ns.SlicedCard(home, WIDE_CARD, SIZE.edge)
  card:SetPoint("TOPLEFT", 5, -41)
  card:SetPoint("RIGHT", home, "RIGHT", -4, 0)
  card:SetHeight(SIZE.header)
  home.guild = Text(card, "GameFontNormal")
  home.guild:SetPoint("TOPLEFT", 20, -16)
  home.sync = Text(card, "GameFontHighlightSmall")
  home.sync:SetPoint("TOPLEFT", home.guild, "BOTTOMLEFT", 0, -6)
  home.peers = Text(card, "GameFontHighlightSmall", "RIGHT")
  home.peers:SetPoint("TOPRIGHT", -24, -36)
  home.retry = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
  home.retry:SetSize(170, 20)
  home.retry:SetPoint("TOPRIGHT", -20, -10)
  home.retry:SetText(L.SYNC_RETRY)
  home.retry:SetScript("OnClick", function()
    GS:CommResume()
    GS:RefreshOverview()
  end)
  home.retry:Hide()
  home.peersTip = CreateFrame("Frame", nil, card)
  home.peersTip:SetAllPoints(home.peers)
  home.peersTip:EnableMouse(true)
  ns.Tip(home.peersTip, L.PEER_VERSIONS, function() return GS:PeerVersionLines() end)
  return card
end

local function BuildFooter(home)
  home.options = ns.BuildPanel(home, {
    { type = "toggle", label = L.SHOW_LAUNCHER,
      get = function() return GS:LauncherShown() end, set = function(on) GS:SetLauncherShown(on) end },
  })
  home.options:SetPoint("BOTTOMLEFT", 14, 4)
  home.options:SetHeight(SIZE.footer)
  home.options:Show()
  home.version = Text(home, "GameFontDisableSmall", "RIGHT")
  home.version:SetPoint("BOTTOMRIGHT", -20, 16)
  home.diagLink = ns.TextLink(home, L.COPY_DIAG, function() GS:ShowCopyBox(L.COPY_DIAG, GS:DiagLines()) end)
  home.diagLink.text:SetPoint("RIGHT", home.version, "LEFT", -14, 0)
end

local function SetMode(home, mode)
  home.mode = mode
  if mode == "pick" then ns.SeedGoalPicker(home.picker) end
  GS:RefreshOverview()
end

local function BuildBook(home, body)
  local book = CreateFrame("Frame", nil, body)
  book:SetAllPoints()
  home.book = book
  home.goal = ns.BuildGoalSection(book, function() SetMode(home, "pick") end)
  home.goal:SetPoint("TOPLEFT", SIZE.pad, -SIZE.top)
  home.goal:SetPoint("RIGHT", book, "RIGHT", -SIZE.pad - 4, 0)
  home.nowTitle = Text(book, "GameFontNormalLarge")
  home.nowTitle:SetText(L.NOW_TITLE)
  home.now = ns.EntryCards(book, NOW_CARD)
  home.list = ns.EntryRows(book)
  for _, list in ipairs({ home.now, home.list }) do
    list:SetPoint("TOPLEFT", home.nowTitle, "BOTTOMLEFT", 0, -10)
    list:SetPoint("RIGHT", book, "RIGHT", -SIZE.pad - 4, 0)
  end
end

function ns.BuildHome(f)
  local home = CreateFrame("Frame", nil, f)
  home:SetAllPoints()
  local header = BuildHeader(home)
  local body = ns.SlicedCard(home, WIDE_CARD, SIZE.edge)
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 5)
  body:SetPoint("BOTTOMRIGHT", -4, SIZE.footer + 5)
  BuildBook(home, body)
  home.picker = ns.BuildGoalPicker(body, function() SetMode(home, nil) end)
  home.picker:SetAllPoints()
  BuildFooter(home)
  return home
end

local function RenderHeader(home)
  local g = Plain(SafeCall(GetGuildInfo, "player"), "string")
  home.guild:SetText(g or L.NO_GUILD)
  home.sync:SetText(GS:OverviewSyncLine())
  home.retry:SetShown(GS:OverviewSyncState() == "slow")
  home.peers:SetText(GS:OverviewPeersLine())
  home.version:SetText(GS:OverviewVersionLine())
end

local function HomeEntry(d)
  local line, open = ns.Headline(d.name and GS.modules[d.name])
  if not open and (d.page or d.options) then open = function() GS:ShowModulePage(d.name) end end
  return { icon = d.icon, title = d.title, line = line or d.status, open = open or d.open, dim = d.state ~= "loaded",
    tip = { d.status, L.COMMAND:format(d.slash) } }
end

local function HomeEntries(rows)
  local out = {}
  for i, d in ipairs(rows) do out[i] = HomeEntry(d) end
  return out
end

local function NowOf(d)
  local mod = d.name and GS.modules[d.name]
  if not (mod and mod.OverviewNow) then return {} end
  return ns.Entries(GS:Call(mod.OverviewNow, mod), d.icon)
end

local function Sooner(a, b)
  if (a.ends ~= nil) ~= (b.ends ~= nil) then return a.ends ~= nil end
  if a.ends ~= b.ends then return a.ends < b.ends end
  return a.order < b.order
end

local function NowEntries(rows, max)
  local out = {}
  for _, d in ipairs(rows) do
    for _, e in ipairs(NowOf(d)) do
      if e.open then
        e.order = #out + 1
        out[#out + 1] = e
      end
    end
  end
  table.sort(out, Sooner)
  for i = #out, max + 1, -1 do out[i] = nil end
  return out
end

local function PlaceNowTitle(home, goalShown)
  home.nowTitle:ClearAllPoints()
  if goalShown then home.nowTitle:SetPoint("TOPLEFT", home.goal, "BOTTOMLEFT", 0, -14)
  else home.nowTitle:SetPoint("TOPLEFT", home.book, "TOPLEFT", SIZE.pad, -SIZE.top) end
end

local function RenderBook(home, rows)
  local goalShown = ns.RenderGoalSection(home.goal)
  PlaceNowTitle(home, goalShown)
  local now = NowEntries(rows, goalShown and NOW_MAX.withGoal or NOW_MAX.alone)
  local fallback = not now[1]
  ns.RenderEntries(home.now, now)
  ns.RenderEntries(home.list, fallback and HomeEntries(rows) or {})
  home.now:SetShown(not fallback)
  home.list:SetShown(fallback)
end

function ns.RenderHome(home, rows)
  RenderHeader(home)
  local picking = home.mode == "pick" and GS:IsOfficer(GS:PlayerKey()) == true
  home.book:SetShown(not picking)
  home.picker:SetShown(picking)
  if picking then ns.RenderGoalPicker(home.picker) else RenderBook(home, rows) end
  home.options.refreshAll()
end
