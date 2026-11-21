local ADDON, ns = ...
local GS = RavenquillExpedition
local H, News = ns.H, ns.News
local SafeCall, Plain = GS.SafeCall, GS.Plain
local T = GS.NewLocale(ns.NewsLocales)

local MEDIA = "Interface\\AddOns\\RavenquillExpedition_Highlights\\Media\\"
H.MASTHEAD, H.DROP_CAPS, H.VIGNETTE, H.DOTTED = MEDIA .. "masthead", MEDIA .. "dropcaps", MEDIA .. "vignette", MEDIA .. "dotted"
H.IN_BRIEF_ART = { deDE = MEDIA .. "inbrief_deDE", enUS = MEDIA .. "inbrief_enUS" }
H.PARCHMENT = "Interface\\QuestFrame\\QuestBG"
H.PARCHMENT_CROP = { 0.03, 0.54, 0.03, 0.6 }
H.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local FONT = { masthead = "Fonts\\MORPHEUS.TTF", base = "Fonts\\FRIZQT__.TTF" }
local INK, INK_SOFT, RULE, PAPER = { 0.17, 0.13, 0.09 }, { 0.36, 0.29, 0.22 }, { 0.48, 0.40, 0.29 }, { 0.92, 0.86, 0.72 }
local WOODCUT = { tint = { 0.86, 0.68, 0.46 }, border = 3, crop = { 0.08, 0.92, 0.08, 0.92 } }
H.INK, H.INK_SOFT, H.RULE, H.PAPER = INK, INK_SOFT, RULE, PAPER
local TIME_HEX = "6b5a45"
local DROP_CAP = { cols = 8, rows = 4, umlauts = { ["\195\132"] = 27, ["\195\150"] = 28, ["\195\156"] = 29 },
  width = { 0.73, 0.8, 0.63, 0.73, 0.64, 0.68, 0.7, 0.67, 0.63, 0.65, 0.73, 0.54, 0.97, 0.79, 0.68, 0.8, 0.72, 0.83, 0.69,
    0.68, 0.65, 0.79, 0.95, 0.66, 0.77, 0.61, 0.73, 0.68, 0.65 } }
local SIZE = { gutter = 24, mainShare = 0.67, secondMin = 110,
  defaultW = 868, defaultH = 716, wideW = 760, wideH = 600, captionLines = 3.8, capLines = 3, dotsW = 512,
  dim = { pad = { 16, 32 }, mast = { 224, 288 }, mastTop = { 4, 10 }, wood = { 68, 100 }, woodGap = { 12, 16 },
    briefArt = { 96, 124 }, earPad = { 6, 8 } },
  font = { masthead = { 30, 38 }, meta = { 10, 12 }, ear = { 9, 11 }, caption = { 9, 11 }, kicker = { 9, 11 },
    head = { 20, 28 }, dek = { 13, 16 }, body = { 12, 14 }, storyHead = { 15, 20 }, briefTitle = { 18, 22 },
    brief = { 11, 13 }, note = { 10, 11 } } }

function H.Upper(text)
  return (text:upper():gsub("\195([\160-\182\184-\190])", function(b) return "\195" .. string.char(b:byte() - 32) end))
end

local function BaseFont()
  local obj = GameFontHighlightSmall
  return Plain(obj and obj.GetFont and obj:GetFont(), "string") or FONT.base
end

local function SetSize(fs, size)
  if fs:SetFont(fs.fontFile or BaseFont(), size, "") == false then fs:SetFontObject("GameFontHighlightSmall") end
end

local function Dim(paper, key) return SIZE.dim[key][paper.wide and 2 or 1] end

local function Text(paper, role, opts)
  opts = opts or {}
  local fs = paper:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs.fontRole, fs.fontFile = role, opts.file
  SetSize(fs, SIZE.font[role][1])
  paper.texts = paper.texts or {}
  paper.texts[#paper.texts + 1] = fs
  local c = opts.color or INK
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetShadowOffset(0, 0)
  fs:SetJustifyH(opts.justify or "LEFT")
  fs:SetJustifyV("TOP")
  return fs
end

local function Rule(parent, w, h, color)
  local c = color or RULE
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(c[1], c[2], c[3], 0.9)
  if w then t:SetWidth(w) end
  t:SetHeight(h or 1)
  return t
end

local function DoubleRule(parent) return { thin = Rule(parent), thick = Rule(parent, nil, 2) } end

local function Height(fs)
  local text = fs:GetText()
  if not text or text == "" then return 0 end
  return Plain(fs:GetStringHeight(), "number") or 0
end

local function Unbounded(fs)
  local width = fs.GetUnboundedStringWidth and Plain(fs:GetUnboundedStringWidth(), "number")
  return width or Plain(fs:GetStringWidth(), "number") or 0
end

local function Lines(paper, fs, n) return Height(fs) >= n * SIZE.font[fs.fontRole][paper.wide and 2 or 1] end

local function Anchor(paper, region, x, y, width)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", paper, "TOPLEFT", x, -y)
  if width then region:SetWidth(width) end
end

local function Place(paper, fs, x, y, width)
  Anchor(paper, fs, x, y, width)
  return y + Height(fs)
end

local function PlaceDouble(paper, rules, x, y, width)
  Anchor(paper, rules.thin, x, y, width)
  Anchor(paper, rules.thick, x, y + 3, width)
  return y + 5
end

local BuildPaper
do
  local function Art(paper, path, role, text)
    local tex = paper:CreateTexture(nil, "ARTWORK")
    local result = tex:SetTexture(path)
    local fs = Text(paper, role, { file = FONT.masthead, justify = "CENTER" })
    fs:SetText(text)
    local loaded = result ~= false
    tex:SetShown(loaded)
    fs:SetShown(not loaded)
    return { texture = tex, text = fs, loaded = loaded, result = result }
  end

  local function Ear(paper)
    local ear = { top = Text(paper, "ear", { justify = "CENTER" }), bottom = Text(paper, "ear", { justify = "CENTER" }), lines = {} }
    for i = 1, 4 do ear.lines[i] = Rule(paper, nil, nil, INK_SOFT) end
    return ear
  end

  local function Head(paper)
    paper.masthead = Art(paper, H.MASTHEAD, "masthead", T.MASTHEAD)
    paper.ears = { Ear(paper), Ear(paper) }
    paper.mastRules = DoubleRule(paper)
    paper.metaLeft = Text(paper, "meta", { color = INK_SOFT })
    paper.metaDate = Text(paper, "meta", { color = INK_SOFT, justify = "RIGHT" })
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
    caption:SetPoint("TOP", frame, "BOTTOM", 0, -4)
    return { frame = frame, icon = icon, caption = caption }
  end

  local function Story(paper)
    return { kicker = Text(paper, "kicker", { color = INK_SOFT }), head = Text(paper, "storyHead"), body = Text(paper, "body"),
      paragraphs = {} }
  end

  local function Brief(paper)
    local brief = { title = Art(paper, H.IN_BRIEF_ART[T.LOCALE] or H.IN_BRIEF_ART.enUS, "briefTitle", T.IN_BRIEF),
      underline = Rule(paper), more = Text(paper, "note", { color = INK_SOFT }), lines = {}, dots = {} }
    for i = 1, News.BRIEF_MAX do
      brief.lines[i] = Text(paper, "brief")
      local dots = paper:CreateTexture(nil, "ARTWORK")
      if dots:SetTexture(H.DOTTED) == false then dots:SetColorTexture(RULE[1], RULE[2], RULE[3], 0.5) end
      dots:SetHeight(1)
      brief.dots[i] = dots
    end
    return brief
  end

  local function Stories(paper)
    local cap = paper:CreateTexture(nil, "ARTWORK")
    cap.loaded = cap:SetTexture(H.DROP_CAPS) ~= false
    paper.lead = { kicker = Text(paper, "kicker", { color = INK_SOFT }), head = Text(paper, "head"),
      dek = Text(paper, "dek", { color = INK_SOFT }), photo = Woodcut(paper), cap = cap, beside = Text(paper, "body"),
      rest = Text(paper, "body"), body = {} }
    paper.pairRule, paper.pairColumnRule, paper.sideRule = Rule(paper), Rule(paper, 1), Rule(paper, 1)
    paper.second, paper.third = Story(paper), Story(paper)
    paper.brief = Brief(paper)
  end
  BuildPaper = function(paper)
    Head(paper)
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

local function PlaceEar(paper, ear, x, mid, side)
  local pad = Dim(paper, "earPad")
  local inner = math.ceil(math.max(Unbounded(ear.top), Unbounded(ear.bottom))) + 2
  local w, h = inner + 2 * pad, Height(ear.top) + Height(ear.bottom) + pad
  local left, top = side == "RIGHT" and x - w or x, math.floor(mid - h / 2)
  local y = Place(paper, ear.top, left + pad, top + pad / 2, inner)
  Place(paper, ear.bottom, left + pad, y, inner)
  local l = ear.lines
  Anchor(paper, l[1], left, top, w)
  Anchor(paper, l[2], left, top + h - 1, w)
  l[3]:SetHeight(h)
  l[4]:SetHeight(h)
  Anchor(paper, l[3], left, top, 1)
  Anchor(paper, l[4], left + w - 1, top, 1)
end

local function FlowHead(paper, w)
  local pad, m, mw, top = Dim(paper, "pad"), paper.masthead, Dim(paper, "mast"), Dim(paper, "mastTop")
  m.texture:SetSize(mw, mw / 4)
  Anchor(paper, m.texture, (w - mw) / 2, top)
  Anchor(paper, m.text, pad, top + 10, w - 2 * pad)
  PlaceEar(paper, paper.ears[1], pad, top + mw / 8, "LEFT")
  PlaceEar(paper, paper.ears[2], w - pad, top + mw / 8, "RIGHT")
  local y = PlaceDouble(paper, paper.mastRules, pad, top + mw / 4 + 2, w - 2 * pad) + 6
  paper.metaDate:ClearAllPoints()
  paper.metaDate:SetPoint("TOPRIGHT", paper, "TOPRIGHT", -pad, -y)
  return Place(paper, paper.metaLeft, pad, y) + 12
end

local DropCap
do
  local function Index(text)
    local letter = text:match("^[A-Z]")
    if letter then return letter:byte() - 64, 1 end
    return DROP_CAP.umlauts[text:sub(1, 2)], 2
  end

  local function Words(fs, words, n)
    fs:SetText(table.concat(words, " ", 1, n))
    return Height(fs)
  end

  local function Beside(fs, first, maxH)
    local words = {}
    for word in first:gmatch("%S+") do words[#words + 1] = word end
    local lo, hi = math.min(1, #words), #words
    while lo < hi do
      local mid = math.ceil((lo + hi) / 2)
      if Words(fs, words, mid) <= maxH then lo = mid else hi = mid - 1 end
    end
    Words(fs, words, lo)
    return table.concat(words, " ", lo + 1)
  end

  local function SetCap(cap, index, h)
    local col, row, share = (index - 1) % DROP_CAP.cols, math.floor((index - 1) / DROP_CAP.cols), DROP_CAP.width[index]
    cap:SetTexCoord(col / DROP_CAP.cols, (col + share) / DROP_CAP.cols, row / DROP_CAP.rows, (row + 1) / DROP_CAP.rows)
    cap:SetSize(math.ceil(h * share), h)
    return math.ceil(h * share) + 3
  end

  DropCap = function(paper, lead, text, x, y, width)
    local index, len = Index(text)
    if not lead.cap.loaded then index = nil end
    lead.cap:SetShown(index ~= nil)
    lead.cap.letter = index and text:sub(1, len)
    lead.beside:SetText("")
    if not index then
      lead.rest:SetText(text)
      return Place(paper, lead.rest, x, y, width) - y
    end
    local capH = Words(lead.beside, { "X" }, 1) * SIZE.capLines
    local capW = SetCap(lead.cap, index, capH)
    Anchor(paper, lead.cap, x, y)
    Anchor(paper, lead.beside, x + capW, y, width - capW)
    local first, more = text:sub(len + 1):match("^([^\n]*)\n?(.*)$")
    local left = Beside(lead.beside, first, capH + 1)
    lead.rest:SetText(left ~= "" and more ~= "" and (left .. "\n" .. more) or (left .. more))
    return Place(paper, lead.rest, x, y + math.max(capH, Height(lead.beside)), width) - y
  end
end

local function SetCaption(paper, caption, text, width)
  local widest = 0
  for word in (text or ""):gmatch("%S+") do
    caption:SetText(word)
    widest = math.max(widest, Unbounded(caption))
  end
  caption:SetWidth(width)
  caption:SetText(widest <= width and text or "")
  if Lines(paper, caption, SIZE.captionLines) then caption:SetText("") end
end

local function FlowLead(paper, x, top, width, limit)
  local lead, wood = paper.lead, Dim(paper, "wood")
  local y = Place(paper, lead.kicker, x, top, width) + 4
  y = Place(paper, lead.head, x, y, width) + 4
  y = Place(paper, lead.dek, x, y, width) + 10
  lead.photo.frame:SetSize(wood, wood)
  Anchor(paper, lead.photo.frame, x, y)
  SetCaption(paper, lead.photo.caption, lead.photo.text, wood)
  local woodEnd = y + wood + 4 + Height(lead.photo.caption)
  local bodyX = x + wood + Dim(paper, "woodGap")
  local bodyH = 0
  Fit(function(text)
    lead.shown = text
    bodyH = DropCap(paper, lead, text, bodyX, y, x + width - bodyX)
    return bodyH
  end, lead.body, limit - y)
  return math.max(woodEnd, y + bodyH)
end

local function FlowStory(paper, st, x, top, width, bottom)
  local y = Place(paper, st.kicker, x, top, width) + 4
  y = Place(paper, st.head, x, y, width) + 5
  Anchor(paper, st.body, x, y, width)
  Fit(Setter(st.body), st.paragraphs, bottom - y)
  return y + Height(st.body)
end

local function FlowPair(paper, x, top, width, bottom)
  local sec, third = paper.second, paper.third
  Anchor(paper, paper.pairRule, x, top + 10, width)
  local y, colW = top + 20, math.floor((width - SIZE.gutter) / 2)
  local thirdEnd, shown = y, third.id ~= nil
  if shown then
    thirdEnd = FlowStory(paper, third, x + colW + SIZE.gutter, y, colW, bottom)
    shown = third.body:GetText() ~= ""
  end
  for _, region in ipairs({ third.kicker, third.head, third.body, paper.pairColumnRule }) do region:SetShown(shown) end
  local secEnd = FlowStory(paper, sec, x, y, shown and colW or width, bottom)
  Anchor(paper, paper.pairColumnRule, x + colW + SIZE.gutter / 2, y)
  paper.pairColumnRule:SetHeight(math.max(1, math.max(secEnd, thirdEnd) - y))
  return math.max(secEnd, shown and thirdEnd or y), shown and { [third.id] = true } or {}
end

local FlowBrief
do
  local function MoreText(issue, list, dropped)
    local extra = (issue and issue.more or 0) + dropped
    if extra > 0 then return (News.Counted(T.MORE_BRIEF, extra, T):gsub("^%l", string.upper)) end
    return list[1] and "" or T.NO_BRIEF
  end

  local function KeptLines(paper, list, ends, bottom)
    local n = math.min(#list, News.BRIEF_MAX)
    for k = n, 1, -1 do
      paper.brief.more:SetText(MoreText(paper.issue, list, #list - k))
      if ends[k] + 8 + Height(paper.brief.more) <= bottom then return k end
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

  local function Title(paper, x, top, width)
    local brief, art = paper.brief, paper.brief.title
    local aw = math.min(width, Dim(paper, "briefArt"))
    art.texture:SetSize(aw, aw / 4)
    Anchor(paper, art.texture, x + (width - aw) / 2, top)
    local y = art.loaded and top + aw / 4 or Place(paper, art.text, x, top, width) + 2
    local rw = math.floor(width * 0.4)
    Anchor(paper, brief.underline, x + (width - rw) / 2, y + 3, rw)
    return y + 4
  end

  FlowBrief = function(paper, x, top, width, bottom, placed)
    local brief, list = paper.brief, BriefList(paper.issue, placed)
    local ends = { [0] = Title(paper, x, top, width) }
    for i, fs in ipairs(brief.lines) do
      local line, dots = list[i], brief.dots[i]
      fs:SetText(line and ("|cff%s%s|r  %s"):format(TIME_HEX, line.time, line.text) or "")
      local y = Place(paper, fs, x, ends[i - 1] + 7, width) + 5
      Anchor(paper, dots, x, y, width)
      dots:SetTexCoord(0, width / SIZE.dotsW, 0, 1)
      ends[i] = y + 1
    end
    local kept = KeptLines(paper, list, ends, bottom)
    for i, fs in ipairs(brief.lines) do
      local shown = i <= kept and fs:GetText() ~= ""
      fs:SetShown(shown)
      brief.dots[i]:SetShown(shown)
    end
    return Place(paper, brief.more, x, ends[kept] + 8, width), kept
  end
end

local function FlowGrid(paper, top, w, h)
  local pad = Dim(paper, "pad")
  local inner, bottom = w - 2 * pad, h - pad
  local mainW = math.floor(inner * SIZE.mainShare)
  local leadEnd = FlowLead(paper, pad, top, mainW, bottom - SIZE.secondMin)
  local pairEnd, placed = FlowPair(paper, pad, leadEnd, mainW, bottom)
  Anchor(paper, paper.sideRule, pad + mainW + SIZE.gutter / 2, top)
  paper.sideRule:SetHeight(math.max(1, bottom - top))
  local briefEnd, kept = FlowBrief(paper, pad + mainW + SIZE.gutter, top, inner - mainW - SIZE.gutter, bottom, placed)
  local used = math.max(pairEnd, briefEnd, leadEnd + SIZE.secondMin)
  return used, table.concat({ kept, tostring(next(placed)), paper.lead.shown or "", paper.second.body:GetText() or "",
    paper.third.body:GetText() or "", paper.lead.photo.caption:GetText() or "" }, "|")
end

local function PaperSize(paper)
  local w, h = Plain(paper:GetWidth(), "number"), Plain(paper:GetHeight(), "number")
  if not (w and w > 0 and h and h > 0) then return SIZE.defaultW, SIZE.defaultH end
  return w, h
end

local function Scale(paper, w, h)
  local wide = w >= SIZE.wideW and h >= SIZE.wideH
  if paper.wide == wide then return end
  paper.wide = wide
  for _, fs in ipairs(paper.texts) do SetSize(fs, SIZE.font[fs.fontRole][wide and 2 or 1]) end
end

local function Flow(paper, w, h)
  if not w then w, h = PaperSize(paper) end
  local reserve = paper.reserve or 0
  h = h - reserve
  Scale(paper, w, math.max(h, (paper.room or 0) - reserve))
  local used, shape = FlowGrid(paper, FlowHead(paper, w), w, h)
  return used + Dim(paper, "pad") + reserve, shape
end

H.SetFontSize, H.FlowPaper, H.DoubleRule = SetSize, Flow, DoubleRule

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

local function DayOf(t) return date("%Y-%m-%d", t) end
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

function H:Issues() return News.Days(self:Log(), DayOf) end

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
    return { k = "quest", kicker = T.EMPTY_KICKER, head = T.EMPTY_HEAD, dek = T.EMPTY_DEK, body = { T.EMPTY_BODY, T.EMPTY_MORE } }
  end

  local function SetEar(ear, top, bottom)
    ear.top:SetText(top)
    ear.bottom:SetText(bottom)
  end

  FillPaper = function(paper, issue)
    paper.issue = issue
    local when = DateVars(issue and issue.t or GS:Now())
    paper.metaLeft:SetText(T.META_LEFT)
    paper.metaDate:SetText(News.Fill(T.SHORT_DATE, when))
    SetEar(paper.ears[1], News.Fill(T.EAR_NO, { no = issue and issue.no or 0 }), when.weekday)
    SetEar(paper.ears[2], T.EAR_PRICE, T.EAR_COST)
    SetLead(paper.lead, issue and issue.lead or EmptyStory())
    SetStory(paper.second, issue and issue.second or NoSecond())
    SetStory(paper.third, issue and issue.extra[1])
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
  local label = issue and News.Fill(T.ISSUE_OF, { date = News.Fill(T.SHORT_DATE, DateVars(issue.t)) })
  f.issueLabel:SetText(label or T.NO_ISSUE)
end

function H:RenderPaper(f)
  local days = self:Issues()
  local i = IssueIndex(days, f.issueDay)
  local issue = days[i] and News.Issue(days[i], T, self:NewsContext())
  FillPaper(f.paper, issue)
  if f.fit then f.fit(f) end
  SetNav(f, i, #days, issue)
end

function H:StepIssue(f, delta)
  local days = self:Issues()
  local target = days[IssueIndex(days, f.issueDay) + delta]
  if target then f.issueDay = target.day end
  self:Refresh()
end
