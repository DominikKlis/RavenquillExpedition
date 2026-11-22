local ADDON, ns = ...
local GS = RavenquillExpedition
local H, News = ns.H, ns.News
local SafeCall, Plain = GS.SafeCall, GS.Plain
local T = GS.NewLocale(ns.NewsLocales)

local MEDIA = "Interface\\AddOns\\RavenquillExpedition_Highlights\\Media\\"
H.MASTHEAD, H.VIGNETTE = MEDIA .. "masthead", MEDIA .. "vignette"
H.PARCHMENT = "Interface\\QuestFrame\\QuestBG"
H.PARCHMENT_CROP = { 0.03, 0.54, 0.03, 0.6 }
H.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
H.TITLE_FONT, H.BASE_FONT = "Fonts\\MORPHEUS.TTF", "Fonts\\FRIZQT__.TTF"
local INK, INK_SOFT, RULE = { 0.114, 0.078, 0.047 }, { 0.29, 0.227, 0.165 }, { 0.612, 0.525, 0.392 }
local ACCENT, PAPER = { 0.478, 0.165, 0.078 }, { 0.937, 0.886, 0.765 }
local WOODCUT = { tint = { 0.86, 0.68, 0.46 }, border = 3, crop = { 0.08, 0.92, 0.08, 0.92 } }
H.INK, H.INK_SOFT, H.RULE, H.ACCENT, H.PAPER = INK, INK_SOFT, RULE, ACCENT, PAPER
local SIZE = { designW = 900, designH = 780, minScale = 0.75, defaultW = 900, defaultH = 780, captionLines = 3.8,
  top = 26, side = 34, mastW = 232, mastH = 58, metaGap = 8, metaPad = 5, headGap = 14, sideW = 250, gap = 22, leadGap = 10,
  dekPad = 8, icon = 110, colGap = 18, captionGap = 4, lowerGap = 12, lowerPad = 10, storyHeadTop = 2, storyHeadGap = 6,
  sidePad = 18, titleGap = 10, itemPad = 8, secondMin = 110, boxPadX = 14, boxPadY = 8 }
local ROLES = { masthead = { 44, 1, true }, meta = { 13, 1 }, caption = { 12, 1.2 }, kicker = { 12, 1 },
  head = { 34, 1.05, true }, dek = { 16, 1.35 }, body = { 15, 1.45 }, storyHead = { 20, 1.15, true }, story = { 14.5, 1.42 },
  briefTitle = { 22, 1, true }, time = { 12, 1 }, brief = { 14, 1.4 }, note = { 12, 1.3 }, figure = { 40, 1, true },
  figureLabel = { 16, 1.2 }, honor = { 24, 1.1, true } }

function H.Upper(text)
  return (text:upper():gsub("\195([\160-\182\184-\190])", function(b) return "\195" .. string.char(b:byte() - 32) end))
end

local function BaseFont()
  local obj = GameFontHighlightSmall
  return Plain(obj and obj.GetFont and obj:GetFont(), "string") or H.BASE_FONT
end

local function SetSize(fs, size)
  if fs.fontFile and fs:SetFont(fs.fontFile, size, "") ~= false then return end
  if fs:SetFont(BaseFont(), size, "") == false then fs:SetFontObject("GameFontHighlightSmall") end
end

local function U(paper, n) return n * paper.scale end

local function ApplyRole(paper, fs)
  local role = ROLES[fs.fontRole]
  local size = U(paper, role[1])
  SetSize(fs, size)
  fs:SetSpacing((role[2] - 1) * size)
end

local function Text(paper, role, opts)
  opts = opts or {}
  local fs = (opts.parent or paper):CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs.fontRole, fs.fontFile = role, ROLES[role][3] and H.TITLE_FONT or nil
  ApplyRole(paper, fs)
  paper.texts[#paper.texts + 1] = fs
  local c = opts.color or INK
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetShadowOffset(0, 0)
  fs:SetJustifyH(opts.justify or "LEFT")
  fs:SetJustifyV("TOP")
  return fs
end

local function Rule(parent, h, color)
  local c = color or RULE
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(c[1], c[2], c[3], 1)
  t:SetHeight(h or 1)
  return t
end

local function Height(fs)
  local text = fs:GetText()
  if not text or text == "" then return 0 end
  return Plain(fs:GetStringHeight(), "number") or 0
end

local function Unbounded(fs)
  local width = fs.GetUnboundedStringWidth and Plain(fs:GetUnboundedStringWidth(), "number")
  return width or Plain(fs:GetStringWidth(), "number") or 0
end

local function Anchor(paper, region, x, y, width)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", paper, "TOPLEFT", x, -y)
  if width then region:SetWidth(width) end
end

local function Place(paper, fs, x, y, width)
  Anchor(paper, fs, x, y, width)
  return y + Height(fs)
end

H.PaperInk = { Text = Text, Rule = Rule, Height = Height, Unbounded = Unbounded, Anchor = Anchor, Place = Place, U = U }

local BuildPaper
do
  local function Masthead(paper)
    local tex = paper:CreateTexture(nil, "ARTWORK")
    local result = tex:SetTexture(H.MASTHEAD)
    local fs = Text(paper, "masthead", { justify = "CENTER" })
    fs:SetText(T.MASTHEAD)
    local loaded = result ~= false
    tex:SetShown(loaded)
    fs:SetShown(not loaded)
    paper.masthead = { texture = tex, text = fs, loaded = loaded, result = result }
  end

  local function Meta(paper)
    paper.meta = { top = Rule(paper, 2, INK), bottom = Rule(paper, 1), left = Text(paper, "meta", { color = INK_SOFT }),
      mid = Text(paper, "meta", { color = INK_SOFT }), right = Text(paper, "meta", { color = INK_SOFT }) }
  end

  local function Woodcut(paper)
    local frame = paper:CreateTexture(nil, "BORDER")
    frame:SetColorTexture(INK[1], INK[2], INK[3], 1)
    local icon = paper:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", WOODCUT.border, -WOODCUT.border)
    icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -WOODCUT.border, WOODCUT.border)
    icon:SetTexCoord(WOODCUT.crop[1], WOODCUT.crop[2], WOODCUT.crop[3], WOODCUT.crop[4])
    icon:SetDesaturated(true)
    icon:SetVertexColor(WOODCUT.tint[1], WOODCUT.tint[2], WOODCUT.tint[3])
    local caption = Text(paper, "caption", { color = INK_SOFT, justify = "CENTER" })
    return { frame = frame, icon = icon, caption = caption }
  end

  local function Story(paper)
    return { kicker = Text(paper, "kicker", { color = ACCENT }), head = Text(paper, "storyHead"), body = Text(paper, "story"),
      paragraphs = {} }
  end

  local function TestsButton(paper)
    local b = CreateFrame("Button", nil, paper)
    b.label = Text(paper, "body", { parent = b, justify = "CENTER" })
    b.label:SetPoint("CENTER")
    if b.SetFontString then b:SetFontString(b.label) end
    b:SetText(ns.L.OPT_TEST)
    H.InkBox(b)
    b:SetScript("OnClick", function() GS:Call(H.AddTestEntries, H) end)
    b:Hide()
    return b
  end

  local function Brief(paper)
    local box = CreateFrame("Frame", nil, paper)
    box:SetAllPoints()
    local brief = { box = box, title = Text(paper, "briefTitle", { parent = box, justify = "CENTER" }),
      more = Text(paper, "note", { parent = box, color = INK_SOFT }), items = {} }
    brief.title:SetText(T.IN_BRIEF)
    for i = 1, News.BRIEF_MAX do
      brief.items[i] = { time = Text(paper, "time", { parent = box, color = ACCENT }), text = Text(paper, "brief", { parent = box }),
        rule = Rule(box, 1) }
    end
    return brief
  end

  local function Stories(paper)
    paper.lead = { kicker = Text(paper, "kicker", { color = ACCENT }), head = Text(paper, "head"),
      dek = Text(paper, "dek", { color = INK_SOFT }), dekRule = Rule(paper, 1), photo = Woodcut(paper),
      columns = { Text(paper, "body"), Text(paper, "body") }, body = {}, tests = TestsButton(paper) }
    paper.pairRule, paper.sideRule = Rule(paper, 2, INK), Rule(paper, nil, INK)
    paper.sideRule:SetWidth(2)
    paper.second, paper.third = Story(paper), Story(paper)
    paper.brief, paper.week = Brief(paper), H.WeekColumn(paper)
  end

  BuildPaper = function(paper)
    paper.texts, paper.scale = {}, 1
    Masthead(paper)
    Meta(paper)
    Stories(paper)
  end
end

local function Setter(fs)
  return function(text)
    fs:SetText(text)
    return Height(fs)
  end
end

local function Fit(set, paragraphs, maxH)
  for n = #paragraphs, 1, -1 do
    if set(table.concat(paragraphs, "\n", 1, n)) <= maxH then return end
  end
  local sentences = News.Sentences(paragraphs[1] or "")
  for n = #sentences - 1, 1, -1 do
    if set(table.concat(sentences, " ", 1, n)) <= maxH then return end
  end
  set("")
end

local FlowColumns
do
  local function Tokens(text)
    local out = {}
    for word, gap in text:gmatch("(%S+)(%s*)") do out[#out + 1] = { word, gap } end
    return out
  end

  local function Join(tokens, from, to)
    local parts = {}
    for i = from, to do
      parts[#parts + 1] = tokens[i][1]
      if i < to then parts[#parts + 1] = tokens[i][2] end
    end
    return table.concat(parts)
  end

  local function Split(cols, tokens, k)
    cols[1]:SetText(Join(tokens, 1, k))
    cols[2]:SetText(Join(tokens, k + 1, #tokens))
    return Height(cols[1]), Height(cols[2])
  end

  local function Search(lo, hi, ok)
    while lo < hi do
      local mid = math.floor((lo + hi) / 2)
      if ok(mid) then hi = mid else lo = mid + 1 end
    end
    return lo
  end

  local function Tallest(cols, tokens, k)
    local a, b = Split(cols, tokens, k)
    return math.max(a, b)
  end

  local function Balanced(cols, tokens)
    local n = #tokens
    local k = Search(0, n, function(m) local a, b = Split(cols, tokens, m); return a >= b end)
    local best = Tallest(cols, tokens, k)
    if k > 0 then best = math.min(best, Tallest(cols, tokens, k - 1)) end
    return n - Search(0, n, function(m) return Split(cols, tokens, n - m) <= best end)
  end

  FlowColumns = function(paper, cols, text, x, y, width, gap)
    Anchor(paper, cols[1], x, y, width)
    Anchor(paper, cols[2], x + width + gap, y, width)
    local tokens = Tokens(text)
    return Tallest(cols, tokens, Balanced(cols, tokens))
  end
end

local function MetaRow(paper, y, w)
  local meta, side = paper.meta, SIZE.side
  local wl, wm, wr = Unbounded(meta.left), Unbounded(meta.mid), Unbounded(meta.right)
  local gap = (w - 2 * side - wl - wm - wr) / 2
  Anchor(paper, meta.left, side, y)
  Anchor(paper, meta.mid, side + wl + gap, y)
  meta.right:ClearAllPoints()
  meta.right:SetPoint("TOPRIGHT", paper, "TOPRIGHT", -side, -y)
  return y + math.max(Height(meta.left), Height(meta.mid), Height(meta.right))
end

local function FlowHead(paper, w)
  local side, top, m = SIZE.side, SIZE.top, paper.masthead
  local mw, mh = U(paper, SIZE.mastW), U(paper, SIZE.mastH)
  m.texture:SetSize(mw, mh)
  Anchor(paper, m.texture, (w - mw) / 2, top)
  Anchor(paper, m.text, side, top, w - 2 * side)
  local y = top + mh + U(paper, SIZE.metaGap)
  Anchor(paper, paper.meta.top, side, y, w - 2 * side)
  y = MetaRow(paper, y + 2 + U(paper, SIZE.metaPad), w) + U(paper, SIZE.metaPad)
  Anchor(paper, paper.meta.bottom, side, y, w - 2 * side)
  return y + 1 + U(paper, SIZE.headGap)
end

local function SetCaption(paper, caption, text, width)
  local widest = 0
  for word in (text or ""):gmatch("%S+") do
    caption:SetText(word)
    widest = math.max(widest, Unbounded(caption))
  end
  caption:SetWidth(width)
  caption:SetText(widest <= width and text or "")
  if Height(caption) >= SIZE.captionLines * U(paper, ROLES.caption[1]) then caption:SetText("") end
end

local function FlowPhoto(paper, photo, x, y)
  local size = U(paper, SIZE.icon)
  photo.frame:SetSize(size, size)
  Anchor(paper, photo.frame, x, y)
  SetCaption(paper, photo.caption, photo.text, size)
  return Place(paper, photo.caption, x, y + size + U(paper, SIZE.captionGap), size)
end

local function SizeTests(paper, b)
  local h = Height(b.label) + 2 * U(paper, SIZE.boxPadY)
  b:SetSize(Unbounded(b.label) + 2 * U(paper, SIZE.boxPadX), h)
  return h
end

local function PlaceTests(paper, lead, y, colX, colW, gap)
  local b, h1, h2 = lead.tests, Height(lead.columns[1]), Height(lead.columns[2])
  local x, top = colX, y + math.max(h1, h2)
  if h2 > 0 and (Plain(b:GetWidth(), "number") or 0) <= colW then x, top = colX + colW + U(paper, SIZE.colGap), y + h2 end
  Anchor(paper, b, x, top + gap)
  return top + gap + (Plain(b:GetHeight(), "number") or 0)
end

local function FlowLead(paper, x, top, width, limit)
  local lead, gap = paper.lead, U(paper, SIZE.leadGap)
  local y = Place(paper, lead.kicker, x, top, width) + gap
  y = Place(paper, lead.head, x, y, width) + gap
  y = Place(paper, lead.dek, x, y, width) + U(paper, SIZE.dekPad)
  Anchor(paper, lead.dekRule, x, y, width)
  y = y + 1 + gap
  local photoEnd = FlowPhoto(paper, lead.photo, x, y)
  local colGap = U(paper, SIZE.colGap)
  local colX = x + U(paper, SIZE.icon) + colGap
  local colW = (x + width - colX - colGap) / 2
  local bodyH, reserve = 0, 0
  if lead.tests:IsShown() then reserve = SizeTests(paper, lead.tests) + gap end
  Fit(function(text)
    lead.shown = text
    bodyH = FlowColumns(paper, lead.columns, text, colX, y, colW, colGap)
    return bodyH
  end, lead.body, limit - y - reserve)
  if reserve > 0 then return math.max(photoEnd, PlaceTests(paper, lead, y, colX, colW, gap)) end
  return math.max(photoEnd, y + bodyH)
end

local function FlowStory(paper, st, x, top, width, bottom)
  local y = Place(paper, st.kicker, x, top, width) + U(paper, SIZE.storyHeadTop)
  y = Place(paper, st.head, x, y, width) + U(paper, SIZE.storyHeadGap)
  Anchor(paper, st.body, x, y, width)
  Fit(Setter(st.body), st.paragraphs, bottom - y)
  return y + Height(st.body)
end

local function FlowPair(paper, x, top, width, bottom)
  local sec, third, gap = paper.second, paper.third, U(paper, SIZE.gap)
  Anchor(paper, paper.pairRule, x, top, width)
  local y, colW = top + 2 + U(paper, SIZE.lowerPad), (width - gap) / 2
  local thirdEnd, shown = y, third.id ~= nil
  if shown then
    thirdEnd = FlowStory(paper, third, x + colW + gap, y, colW, bottom)
    shown = third.body:GetText() ~= ""
  end
  for _, region in ipairs({ third.kicker, third.head, third.body }) do region:SetShown(shown) end
  local secEnd = FlowStory(paper, sec, x, y, shown and colW or width, bottom)
  return math.max(secEnd, shown and thirdEnd or y), shown and { [third.id] = true } or {}
end

local FlowBrief
do
  local function MoreText(issue, list, dropped)
    local extra = (issue and issue.more or 0) + dropped
    if extra > 0 then return (News.Counted(T.MORE_BRIEF, extra, T):gsub("^%l", string.upper)) end
    return list[1] and "" or T.NO_BRIEF
  end

  local function KeptItems(paper, list, ends, bottom)
    local n = math.min(#list, News.BRIEF_MAX)
    for k = n, 1, -1 do
      paper.brief.more:SetText(MoreText(paper.issue, list, #list - k))
      if ends[k] + Height(paper.brief.more) <= bottom then return k end
    end
    paper.brief.more:SetText(MoreText(paper.issue, list, #list))
    return 0
  end

  local function BriefList(issue, placed)
    local out = {}
    for _, line in ipairs(issue and issue.brief or {}) do
      if not placed[line.id] then out[#out + 1] = line end
    end
    return out
  end

  local function FlowItem(paper, item, line, x, y, width)
    item.time:SetText(line and (line.clock or line.time) or "")
    item.text:SetText(line and line.text or "")
    y = Place(paper, item.time, x, y, width)
    y = Place(paper, item.text, x, y, width) + U(paper, SIZE.itemPad)
    Anchor(paper, item.rule, x, y, width)
    return y + 1 + U(paper, SIZE.itemPad)
  end

  FlowBrief = function(paper, x, top, width, bottom, placed)
    local brief, list = paper.brief, BriefList(paper.issue, placed)
    local ends = { [0] = Place(paper, brief.title, x, top, width) + U(paper, SIZE.titleGap) }
    for i, item in ipairs(brief.items) do ends[i] = FlowItem(paper, item, list[i], x, ends[i - 1], width) end
    local kept = KeptItems(paper, list, ends, bottom)
    for i, item in ipairs(brief.items) do
      local shown = i <= kept and item.text:GetText() ~= ""
      for _, region in pairs(item) do region:SetShown(shown) end
    end
    return Place(paper, brief.more, x, ends[kept], width), kept
  end
end

local function FlowGrid(paper, top, w, bottom)
  local side, gap, sideW = SIZE.side, U(paper, SIZE.gap), U(paper, SIZE.sideW)
  local mainW, secondMin = w - 2 * side - sideW - gap, U(paper, SIZE.secondMin)
  local leadEnd = FlowLead(paper, side, top, mainW, bottom - secondMin)
  local pairEnd, placed = FlowPair(paper, side, leadEnd + U(paper, SIZE.lowerGap), mainW, bottom)
  local sideX = side + mainW + gap
  Anchor(paper, paper.sideRule, sideX, top)
  paper.sideRule:SetHeight(math.max(1, bottom - top))
  local FlowSide = paper.week.shown and H.FlowWeekColumn or FlowBrief
  local briefEnd, kept = FlowSide(paper, sideX + 2 + U(paper, SIZE.sidePad), top, sideW - 2 - U(paper, SIZE.sidePad), bottom,
    placed)
  local used = math.max(pairEnd, briefEnd, leadEnd + secondMin)
  return used, table.concat({ kept, tostring(next(placed)), paper.lead.shown or "", paper.second.body:GetText() or "",
    paper.third.body:GetText() or "", paper.lead.photo.caption:GetText() or "" }, "|")
end

local function PaperSize(paper)
  local w, h = Plain(paper:GetWidth(), "number"), Plain(paper:GetHeight(), "number")
  if not (w and w > 0 and h and h > 0) then return SIZE.defaultW, SIZE.defaultH end
  return w, h
end

local function Scale(paper, w, h)
  local scale = math.max(SIZE.minScale, math.min(1, w / SIZE.designW, h / SIZE.designH))
  if paper.scale == scale then return end
  paper.scale = scale
  for _, fs in ipairs(paper.texts) do ApplyRole(paper, fs) end
end

local function Flow(paper, w, h)
  if not w then w, h = PaperSize(paper) end
  local reserve = paper.reserve or 0
  Scale(paper, w, math.max(h, paper.room or 0))
  local used, shape = FlowGrid(paper, FlowHead(paper, w), w, h - reserve)
  return used + reserve, shape
end

H.SetFontSize, H.FlowPaper = SetSize, Flow

function H:AttachPaper(f, nav)
  local paper = CreateFrame("Frame", nil, f)
  paper:SetAllPoints()
  if paper.SetClipsChildren then paper:SetClipsChildren(true) end
  paper.reserve = nav.reserve
  H.PaperSheet(paper)
  BuildPaper(paper)
  paper:SetScript("OnSizeChanged", function() GS:Call(Flow, paper) end)
  f.paper = paper
  paper:Show()
  H.NavButtons(f, nav, H.InkLayer(f, paper))
end

local DayOf = News.DayOf
local function Clock(t) return date("%H:%M", t) end

local function DateVars(t)
  local d = date("*t", t)
  return { weekday = T.WEEKDAYS[d.wday], day = d.day, month = T.MONTHS[d.month] }
end

local function ItemFacts(id)
  if not id then return nil end
  local name, il = H:CachedItem(id)
  local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local _, _, _, equipLoc, icon = SafeCall(instant, id)
  return { name = name, il = il, equipLoc = Plain(equipLoc, "string"), icon = Plain(icon) }
end

local function Standing(st) return Plain(_G["FACTION_STANDING_LABEL" .. tostring(st)], "string") end

function H:NewsContext()
  return { maxLevel = Plain(SafeCall(GetMaxPlayerLevel), "number"), time = Clock, item = ItemFacts, standing = Standing }
end

local function NewsWorthy(events)
  local out = {}
  for _, e in ipairs(events) do if (H.KINDS[e.k] or {}).paper ~= false then out[#out + 1] = e end end
  return out
end

function H:Issues() return News.Days(NewsWorthy(self:Log()), DayOf) end

local FillPaper
do
  local function KindIcon(k)
    local kind = H.KINDS[k]
    return kind and ("Interface\\Icons\\" .. kind.icon) or H.FALLBACK_ICON
  end

  local function SetPhoto(photo, story)
    if photo.icon:SetTexture(story.icon or KindIcon(story.k)) == false then photo.icon:SetTexture(H.FALLBACK_ICON) end
    photo.text = story.caption
  end

  local function SetLead(lead, story)
    lead.kicker:SetText(H.Upper(story.kicker or ""))
    lead.head:SetText(story.head)
    lead.dek:SetText(story.dek or "")
    lead.body = story.body
    lead.tests:SetShown(story.offersTests == true)
    SetPhoto(lead.photo, story)
  end

  local function SetStory(st, story)
    st.id = story and story.id
    st.kicker:SetText(H.Upper(story and story.kicker or ""))
    st.head:SetText(story and story.head or "")
    st.paragraphs = story and story.body or {}
  end

  local function NoSecond() return { kicker = T.NO_SECOND_KICKER, head = T.NO_SECOND_HEAD, body = { T.NO_SECOND_BODY } } end

  local function EmptyStory()
    return { k = "quest", kicker = T.EMPTY_KICKER, head = T.EMPTY_HEAD, dek = T.EMPTY_DEK, body = { T.EMPTY_BODY },
      offersTests = true }
  end

  local function SetMeta(meta, issue, when)
    meta.left:SetText(T.META_LEFT)
    meta.mid:SetText(when.weekday .. ", " .. News.Fill(T.SHORT_DATE, when))
    meta.right:SetText(News.Fill(T.EAR_NO, { no = issue and issue.no or 0 }) .. " · " .. T.EAR_COST)
  end

  FillPaper = function(paper, issue)
    paper.issue = issue
    local when = DateVars(issue and issue.t or GS:Now())
    SetMeta(paper.meta, issue, when)
    SetLead(paper.lead, issue and issue.lead or EmptyStory())
    SetStory(paper.second, issue and issue.second or NoSecond())
    SetStory(paper.third, issue and issue.extra[1])
    H.FillWeekColumn(paper, issue and issue.week)
    Flow(paper)
  end
end

local function IssueIndex(days, day)
  for i, rec in ipairs(days) do if rec.day == day then return i end end
  return #days
end

local function SetNav(f, i, n, issue)
  H.SetEnabled(f.prev, i > 1)
  H.SetEnabled(f.next, i < n)
  local label = issue and News.Fill(issue.week and T.SUNDAY_EDITION or T.ISSUE_OF,
    { date = News.Fill(T.SHORT_DATE, DateVars(issue.t)), week = issue.week and issue.week.no })
  f.issueLabel:SetText(label or T.NO_ISSUE)
  H.SpreadNav(f)
end

function H:RenderPaper(f)
  local days = self:Issues()
  local i, ctx = IssueIndex(days, f.issueDay), self:NewsContext()
  local issue = days[i] and News.Issue(days[i], T, ctx)
  if issue then issue.week = News.SundayEdition(days, i, T, ctx) end
  FillPaper(f.paper, issue)
  if f.fit then f.fit(f) end
  SetNav(f, i, #days, issue)
end

local function PaperLineText(today, now)
  if not today then return T.TEASER_LAST end
  return News.Sunday(now) and T.NOW_SUNDAY or T.TEASER_TODAY
end

function H:PaperLine()
  local days = self:Issues()
  local last = days[#days]
  if not last then return nil end
  local issue, now = News.Issue(last, T, self:NewsContext()), GS:Now()
  return News.Fill(PaperLineText(last.day == DayOf(now), now), { head = issue.lead.head })
end

function H:StepIssue(f, delta)
  local days = self:Issues()
  local target = days[IssueIndex(days, f.issueDay) + delta]
  if target then f.issueDay = target.day end
  self:Refresh()
end
