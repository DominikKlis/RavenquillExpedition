local ADDON, ns = ...
local GS = ns.GS
local SafeCall, Plain = GS.SafeCall, GS.Plain
local L = GS.OverviewL
local Text = ns.Text

local WIDE_CARD = "Profession-overview-Card"
local SIZE = { edge = 24, top = 41, header = 62, footer = 62, pad = 20, gap = 14, bottom = 10 }
local SECTION = { title = 20, below = 6, after = 10 }
local NOW_CARD = { height = 44, gap = 6, icon = 32, inset = 10 }
local NOW_MAX, FEED_MAX, MIN_ROWS = 2, 5, 3

local function BuildHeader(home)
  local card = ns.SlicedCard(home, WIDE_CARD, SIZE.edge)
  card:SetPoint("TOPLEFT", 5, -SIZE.top)
  card:SetPoint("RIGHT", home, "RIGHT", -4, 0)
  card:SetHeight(SIZE.header)
  home.guild = Text(card, "GameFontNormal")
  home.guild:SetPoint("TOPLEFT", 20, -16)
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
  ns.Tip(home.retry, L.SYNC_RETRY, function() return { GS:OverviewSyncLine() } end)
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

local function Section(book, list)
  list.heading = Text(book, "GameFontNormalLarge")
  list:SetPoint("TOPLEFT", list.heading, "BOTTOMLEFT", 0, -SECTION.below)
  list:SetPoint("RIGHT", book, "RIGHT", -SIZE.pad - 4, 0)
  return list
end

local function BuildBook(home, body)
  local book = CreateFrame("Frame", nil, body)
  book:SetAllPoints()
  home.book = book
  home.goal = ns.BuildGoalSection(book, function() SetMode(home, "pick") end)
  home.goal:SetPoint("TOPLEFT", SIZE.pad, -SIZE.gap)
  home.goal:SetPoint("RIGHT", book, "RIGHT", -SIZE.pad - 4, 0)
  home.now = Section(book, ns.NowCards(book, NOW_CARD))
  home.list = Section(book, ns.EntryRows(book))
  home.online = Section(book, ns.RosterRows(book))
  home.feeds = {}
end

function ns.BuildHome(f, height)
  local home = CreateFrame("Frame", nil, f)
  home:SetAllPoints()
  local header = BuildHeader(home)
  local body = ns.SlicedCard(home, WIDE_CARD, SIZE.edge)
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 5)
  body:SetPoint("BOTTOMRIGHT", -4, SIZE.footer + 5)
  home.room = height - SIZE.top - SIZE.header - SIZE.footer - SIZE.bottom
  BuildBook(home, body)
  home.picker = ns.BuildGoalPicker(body, function() SetMode(home, nil) end)
  home.picker:SetAllPoints()
  BuildFooter(home)
  return home
end

local function RenderHeader(home)
  local g = Plain(SafeCall(GetGuildInfo, "player"), "string")
  home.guild:SetText(g or L.NO_GUILD)
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

local function FeedList(home, name)
  if not home.feeds[name] then home.feeds[name] = Section(home.book, ns.FeedRows(home.book)) end
  return home.feeds[name]
end

local function FeedSections(home, rows)
  local out = {}
  for _, d in ipairs(rows) do
    local feed = d.name and ns.Feed(GS.modules[d.name], FEED_MAX, function() GS:ShowModulePage(d.name) end)
    if feed then out[#out + 1] = { title = feed.title, rows = feed.rows, list = FeedList(home, d.name) } end
  end
  return out
end

local function MoreOnline(n) return { name = L.ONLINE_MORE:format(n), more = true } end

local function NowSection(home, rows)
  local list, entries = home.now, NowEntries(rows, NOW_MAX)
  if not entries[1] then list, entries = home.list, HomeEntries(rows) end
  return { title = L.NOW_TITLE, list = list, rows = entries, min = #entries }
end

local function Sections(home, rows)
  local out = { NowSection(home, rows) }
  for _, s in ipairs(FeedSections(home, rows)) do out[#out + 1] = s end
  out[#out + 1] = { title = L.ONLINE_TITLE, list = home.online, rows = GS:OnlineGuildmates(), more = MoreOnline }
  return out
end

local function ClearLists(home)
  local lists = { home.now, home.list, home.online }
  for _, list in pairs(home.feeds) do lists[#lists + 1] = list end
  for _, list in ipairs(lists) do
    ns.RenderEntries(list, {})
    list.heading:Hide()
    list:Hide()
  end
end

local function NextCost(s, n)
  local step = s.list.style.Step(s.list)
  if n == 0 then return SECTION.title + SECTION.below + step + SECTION.after end
  return step
end

local function Grow(sections, counts, room, limit)
  for i, s in ipairs(sections) do
    local want = math.min(#s.rows, limit(s))
    while counts[i] < want and NextCost(s, counts[i]) <= room do
      room = room - NextCost(s, counts[i])
      counts[i] = counts[i] + 1
    end
  end
  return room
end

local function Fit(sections, room)
  local counts = {}
  for i in ipairs(sections) do counts[i] = 0 end
  room = Grow(sections, counts, room, function(s) return s.min or MIN_ROWS end)
  Grow(sections, counts, room, function(s) return #s.rows end)
  return counts
end

local function Visible(s, n)
  local rows = {}
  for i = 1, n do rows[i] = s.rows[i] end
  if #s.rows > n and s.more then rows[n] = s.more(#s.rows - n + 1) end
  return rows
end

local function Place(home, s, y, n)
  local heading = s.list.heading
  heading:ClearAllPoints()
  heading:SetPoint("TOPLEFT", home.book, "TOPLEFT", SIZE.pad, -y)
  heading:SetText(s.title)
  heading:Show()
  ns.RenderEntries(s.list, Visible(s, n))
  s.list:Show()
  return y + SECTION.title + SECTION.below + n * s.list.style.Step(s.list) + SECTION.after
end

local function Stack(home, sections, y)
  ClearLists(home)
  local counts = Fit(sections, home.room + SECTION.after - y)
  for i, s in ipairs(sections) do
    if counts[i] > 0 then y = Place(home, s, y, counts[i]) end
  end
end

local function RenderBook(home, rows)
  local goalHeight = ns.RenderGoalSection(home.goal)
  Stack(home, Sections(home, rows), SIZE.gap + (goalHeight and goalHeight + SIZE.gap or 0))
end

function ns.RenderHome(home, rows)
  RenderHeader(home)
  local picking = home.mode == "pick" and GS:IsOfficer(GS:PlayerKey()) == true
  home.book:SetShown(not picking)
  home.picker:SetShown(picking)
  if picking then ns.RenderGoalPicker(home.picker) else RenderBook(home, rows) end
  home.options.refreshAll()
end
