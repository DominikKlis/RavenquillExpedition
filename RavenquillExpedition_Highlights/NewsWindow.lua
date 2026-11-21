local ADDON, ns = ...
local GS = RavenquillExpedition
local H, News = ns.H, ns.News
local SafeCall, Plain = GS.SafeCall, GS.Plain
local T = GS.NewLocale(ns.NewsLocales)

H.MASTHEAD = "Interface\\AddOns\\RavenquillExpedition_Highlights\\Media\\masthead"
H.PARCHMENT = "Interface\\QuestFrame\\QuestBG"
H.PARCHMENT_CROP = { 0.03, 0.54, 0.03, 0.6 }
H.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local GRAIN_ALPHA = 0.5
local MASTHEAD_FONT = "Fonts\\MORPHEUS.TTF"
local BASE_FONT = "Fonts\\FRIZQT__.TTF"
local INK, INK_SOFT, RULE, PAPER = { 0.17, 0.13, 0.09 }, { 0.36, 0.29, 0.22 }, { 0.48, 0.40, 0.29 }, { 0.92, 0.86, 0.72 }
local LABEL = { 0.85, 0.78, 0.62 }
H.INK, H.INK_SOFT = INK, INK_SOFT
local TIME_HEX = "6b5a45"
local SIZE = { pad = 16, photoW = 64, photoH = 52, gutter = 16, briefGap = 24, leadTop = 97, minColumn = 180, secondMin = 110,
  leftShare = 0.57, defaultW = 868, defaultH = 716, wideW = 760, wideH = 600,
  font = { masthead = { 30, 30 }, meta = { 10, 11 }, caption = { 9, 10 }, kicker = { 10, 11 }, head = { 20, 28 },
    dek = { 13, 16 }, body = { 12, 14 }, secondHead = { 16, 20 }, briefTitle = { 18, 22 }, brief = { 11, 13 },
    note = { 10, 11 } } }

local function BaseFont()
  local obj = GameFontHighlightSmall
  return Plain(obj and obj.GetFont and obj:GetFont(), "string") or BASE_FONT
end

local function SetSize(fs, size)
  if fs:SetFont(fs.fontFile or BaseFont(), size, "") == false then fs:SetFontObject("GameFontHighlightSmall") end
end

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

local function Rule(parent, w, h)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(RULE[1], RULE[2], RULE[3], 0.9)
  if w then t:SetWidth(w) end
  t:SetHeight(h or 1)
  return t
end

local function TopRule(paper, y)
  local t = Rule(paper)
  t:SetPoint("TOPLEFT", SIZE.pad, y)
  t:SetPoint("TOPRIGHT", -SIZE.pad, y)
  return t
end

local function FileOK(path)
  if type(GetFileIDFromPath) ~= "function" then return true end
  local ok, id = pcall(GetFileIDFromPath, path)
  return ok and Plain(id) ~= nil
end

local function Parchment(paper)
  local base = paper:CreateTexture(nil, "BACKGROUND", nil, -8)
  base:SetAllPoints()
  base:SetColorTexture(PAPER[1], PAPER[2], PAPER[3], 1)
  local grain = paper:CreateTexture(nil, "BACKGROUND", nil, -7)
  grain:SetAllPoints()
  local loaded = FileOK(H.PARCHMENT) and grain:SetTexture(H.PARCHMENT) ~= false
  local crop = H.PARCHMENT_CROP
  if loaded then
    grain:SetTexCoord(crop[1], crop[2], crop[3], crop[4])
    grain:SetAlpha(GRAIN_ALPHA)
  end
  grain:SetShown(loaded)
  paper.parchment = { base = base, texture = grain, source = loaded and "texture" or "color" }
end

local function Masthead(paper)
  local tex = paper:CreateTexture(nil, "ARTWORK")
  tex:SetSize(224, 56)
  tex:SetPoint("TOP", 0, -6)
  local result = tex:SetTexture(H.MASTHEAD)
  local fs = Text(paper, "masthead", { file = MASTHEAD_FONT, justify = "CENTER" })
  fs:SetPoint("TOP", 0, -16)
  fs:SetText(T.MASTHEAD)
  local loaded = result ~= false
  tex:SetShown(loaded)
  fs:SetShown(not loaded)
  paper.masthead = { texture = tex, text = fs, loaded = loaded, result = result }
end

local function Meta(paper)
  TopRule(paper, -66)
  TopRule(paper, -69)
  paper.metaLeft = Text(paper, "meta", { color = INK_SOFT })
  paper.metaLeft:SetPoint("TOPLEFT", SIZE.pad, -74)
  paper.metaDate = Text(paper, "meta", { color = INK_SOFT, justify = "CENTER" })
  paper.metaDate:SetPoint("TOP", 0, -74)
  paper.metaRight = Text(paper, "meta", { color = INK_SOFT, justify = "RIGHT" })
  paper.metaRight:SetPoint("TOPRIGHT", -SIZE.pad, -74)
  TopRule(paper, -89)
end

local function Photo(paper)
  local frame = paper:CreateTexture(nil, "BORDER")
  frame:SetColorTexture(0.11, 0.08, 0.05, 1)
  frame:SetSize(SIZE.photoH, SIZE.photoH)
  local icon = paper:CreateTexture(nil, "ARTWORK")
  icon:SetSize(48, 48)
  icon:SetPoint("CENTER", frame, "CENTER")
  icon:SetDesaturated(true)
  icon:SetVertexColor(0.92, 0.80, 0.62)
  local caption = Text(paper, "caption", { color = INK_SOFT, justify = "CENTER" })
  caption:SetPoint("TOP", frame, "BOTTOM", 0, -3)
  caption:SetWidth(SIZE.photoW - 4)
  return { frame = frame, icon = icon, caption = caption }
end

local function Stories(paper)
  local soft = { color = INK_SOFT }
  paper.lead = { kicker = Text(paper, "kicker", soft), head = Text(paper, "head"), dek = Text(paper, "dek", soft),
    col1 = Text(paper, "body"), col2 = Text(paper, "body"), colRule = Rule(paper, 1), photo = Photo(paper), body = {} }
  paper.rowRules = { Rule(paper), Rule(paper) }
  paper.vrule = Rule(paper, 1)
  paper.second = { kicker = Text(paper, "kicker", soft), head = Text(paper, "secondHead"), body = Text(paper, "body"),
    paragraphs = {} }
  local brief = { title = Text(paper, "briefTitle", { file = MASTHEAD_FONT }), more = Text(paper, "note", soft),
    lines = {} }
  brief.title:SetText(T.IN_BRIEF)
  for i = 1, News.BRIEF_MAX do brief.lines[i] = Text(paper, "brief") end
  paper.brief = brief
end

local function Height(fs)
  local text = fs:GetText()
  if not text or text == "" then return 0 end
  return Plain(fs:GetStringHeight(), "number") or 0
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

local function Fits(fs, text, maxH)
  fs:SetText(text)
  return Height(fs) <= maxH
end

local function Fit(fs, paragraphs, maxH)
  for n = #paragraphs, 1, -1 do
    if Fits(fs, table.concat(paragraphs, "\n", 1, n), maxH) then return end
  end
  local sentences = News.Sentences(paragraphs[1] or "")
  for n = #sentences - 1, 1, -1 do
    if Fits(fs, table.concat(sentences, " ", 1, n), maxH) then return end
  end
  fs:SetText("")
end

local Columns
do
  local function Halves(text)
    local sentences, run, best, gap = News.Sentences(text), 0, nil, math.huge
    for i = 1, #sentences - 1 do
      run = run + #sentences[i] + 1
      if math.abs(#text - 2 * run) < gap then best, gap = i, math.abs(#text - 2 * run) end
    end
    if best then return table.concat(sentences, " ", 1, best), table.concat(sentences, " ", best + 1) end
  end

  Columns = function(body, width)
    local colW = math.floor((width - SIZE.gutter) / 2)
    local first, second = Halves(table.concat(body, " "))
    if second and colW >= SIZE.minColumn then return colW, { first }, { second } end
    return width, body, {}
  end
end

local function FlowColumns(paper, lead, top, inner, maxH)
  local x = SIZE.pad + SIZE.photoW
  local colW, first, second = Columns(lead.body, inner - SIZE.photoW)
  Anchor(paper, lead.col1, x, top, colW)
  Fit(lead.col1, first, maxH)
  Anchor(paper, lead.col2, x + colW + SIZE.gutter, top, colW)
  Fit(lead.col2, lead.col1:GetText() == first[1] and second or {}, maxH)
  local split = Height(lead.col2) > 0
  lead.col2:SetShown(split)
  lead.colRule:SetShown(split)
  local bottom = top + math.max(Height(lead.col1), Height(lead.col2))
  Anchor(paper, lead.colRule, x + colW + SIZE.gutter / 2, top)
  lead.colRule:SetHeight(math.max(1, bottom - top))
  return bottom
end

local function FlowLead(paper, w, h)
  local lead, inner = paper.lead, w - 2 * SIZE.pad
  local y = Place(paper, lead.kicker, SIZE.pad, SIZE.leadTop, inner) + 4
  y = Place(paper, lead.head, SIZE.pad, y, inner) + 5
  y = Place(paper, lead.dek, SIZE.pad, y, inner) + 8
  Anchor(paper, lead.photo.frame, SIZE.pad + 2, y)
  local photoBottom = y + SIZE.photoH + 3 + Height(lead.photo.caption)
  return math.max(photoBottom, FlowColumns(paper, lead, y, inner, h - SIZE.pad - SIZE.secondMin - y))
end

local function FlowStory(paper, top, width, bottom)
  local sec = paper.second
  local y = Place(paper, sec.kicker, SIZE.pad, top, width) + 4
  y = Place(paper, sec.head, SIZE.pad, y, width) + 5
  Anchor(paper, sec.body, SIZE.pad, y, width)
  Fit(sec.body, sec.paragraphs, bottom - y)
end

local function MoreText(issue, dropped)
  local extra = (issue and issue.more or 0) + dropped
  if extra > 0 then return (News.Counted(T.MORE_BRIEF, extra, T):gsub("^%l", string.upper)) end
  return (issue and issue.brief[1]) and "" or T.NO_BRIEF
end

local function KeptLines(paper, ends, bottom)
  local issue = paper.issue
  local n = issue and #issue.brief or 0
  for k = n, 1, -1 do
    paper.brief.more:SetText(MoreText(issue, n - k))
    if ends[k] + 8 + Height(paper.brief.more) <= bottom then return k end
  end
  paper.brief.more:SetText(MoreText(issue, n))
  return 0
end

local function FlowBrief(paper, x, top, width, bottom)
  local brief = paper.brief
  local ends = { [0] = Place(paper, brief.title, x, top, width) }
  for i, fs in ipairs(brief.lines) do
    Anchor(paper, fs, x, ends[i - 1] + 6, width)
    ends[i] = ends[i - 1] + 6 + Height(fs)
  end
  local kept = KeptLines(paper, ends, bottom)
  for i, fs in ipairs(brief.lines) do fs:SetShown(i <= kept and fs:GetText() ~= "") end
  Place(paper, brief.more, x, ends[kept] + 8, width)
end

local function FlowRow(paper, top, w, h)
  local inner = w - 2 * SIZE.pad
  local leftW, bottom = math.floor(inner * SIZE.leftShare), h - SIZE.pad
  Anchor(paper, paper.rowRules[1], SIZE.pad, top + 6, inner)
  Anchor(paper, paper.rowRules[2], SIZE.pad, top + 9, inner)
  local y = top + 20
  FlowStory(paper, y, leftW, bottom)
  Anchor(paper, paper.vrule, SIZE.pad + leftW + SIZE.briefGap / 2, y)
  paper.vrule:SetHeight(math.max(1, bottom - y))
  FlowBrief(paper, SIZE.pad + leftW + SIZE.briefGap, y, inner - leftW - SIZE.briefGap, bottom)
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

local function Flow(paper)
  local w, h = PaperSize(paper)
  h = h - (paper.reserve or 0)
  Scale(paper, w, h)
  FlowRow(paper, FlowLead(paper, w, h), w, h)
end

local function NavButtons(f, nav, ink)
  local host = ink or f
  local function Button(text, width)
    if ink then return H.InkButton(ink, text, width, 13) end
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
  end
  f.prev = Button(T.PREV, 168)
  f.prev:SetPoint("BOTTOMLEFT", nav[1], nav[2])
  f.modeButton = Button(T.CHRONICLE, 90)
  f.modeButton:SetPoint("BOTTOMRIGHT", -nav[1], nav[2])
  f.next = Button(T.NEXT, 168)
  f.next:SetPoint("RIGHT", f.modeButton, "LEFT", -10, 0)
  f.issueLabel = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.issueLabel:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
  f.issueLabel:SetPoint("RIGHT", f.next, "LEFT", -4, 0)
  f.issueLabel:SetJustifyH("CENTER")
  local label = ink and INK_SOFT or LABEL
  f.issueLabel:SetTextColor(label[1], label[2], label[3])
  f.prev:SetScript("OnClick", function() GS:Call(H.StepIssue, H, f, -1) end)
  f.next:SetScript("OnClick", function() GS:Call(H.StepIssue, H, f, 1) end)
  f.modeButton:SetScript("OnClick", function() GS:Call(H.SetViewMode, H, f, f.mode == "paper" and "log" or "paper") end)
end

H.PaperSheet, H.SetFontSize = Parchment, SetSize

function H:AttachPaper(f, insets, nav)
  local paper = CreateFrame("Frame", nil, f)
  paper:SetPoint("TOPLEFT", insets[1], insets[2])
  paper:SetPoint("BOTTOMRIGHT", insets[3], insets[4])
  if paper.SetClipsChildren then paper:SetClipsChildren(true) end
  paper.reserve = nav.reserve
  Parchment(paper)
  Masthead(paper)
  Meta(paper)
  Stories(paper)
  paper:SetScript("OnSizeChanged", function() GS:Call(Flow, paper) end)
  f.paper = paper
  NavButtons(f, nav, nav.ink and H.InkLayer(f, paper))
  f.paperWidgets = { paper, f.prev, f.next, f.issueLabel }
end

function H:ApplyWindowMode(f)
  local paperMode = f.mode == "paper"
  for _, w in ipairs(f.paperWidgets) do w:SetShown(paperMode) end
  for _, w in ipairs(f.logWidgets) do w:SetShown(not paperMode) end
  f.modeButton:SetText(paperMode and T.CHRONICLE or T.PAPER)
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

local function KindIcon(k)
  local kind = H.KINDS[k]
  return kind and ("Interface\\Icons\\" .. kind.icon) or H.FALLBACK_ICON
end

local function SetPhoto(photo, story)
  if photo.icon:SetTexture(story.icon or KindIcon(story.k)) == false then photo.icon:SetTexture(H.FALLBACK_ICON) end
  photo.caption:SetText(story.caption or "")
end

local function SetLead(lead, story)
  lead.kicker:SetText(story.kicker or "")
  lead.head:SetText(story.head)
  lead.dek:SetText(story.dek or "")
  lead.body = story.body
  SetPhoto(lead.photo, story)
end

local function SetSecond(sec, story)
  sec.kicker:SetText(story and story.kicker or T.NO_SECOND_KICKER)
  sec.head:SetText(story and story.head or T.NO_SECOND_HEAD)
  sec.paragraphs = story and story.body or { T.NO_SECOND_BODY }
end

local function SetBrief(brief, issue)
  local lines = issue and issue.brief or {}
  for i, fs in ipairs(brief.lines) do
    local line = lines[i]
    fs:SetText(line and ("|cff%s%s|r  %s"):format(TIME_HEX, line.time, line.text) or "")
  end
end

local function EmptyStory()
  return { k = "quest", kicker = T.EMPTY_KICKER, head = T.EMPTY_HEAD, dek = T.EMPTY_DEK, body = { T.EMPTY_BODY, T.EMPTY_MORE } }
end

local function FillPaper(paper, issue)
  paper.issue = issue
  paper.metaLeft:SetText(T.META_LEFT)
  paper.metaDate:SetText(News.Fill(T.DATE, DateVars(issue and issue.t or GS:Now())))
  paper.metaRight:SetText(News.Fill(T.META_RIGHT, { no = issue and issue.no or 0 }))
  SetLead(paper.lead, issue and issue.lead or EmptyStory())
  SetSecond(paper.second, issue and issue.second)
  SetBrief(paper.brief, issue)
  Flow(paper)
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
  SetNav(f, i, #days, issue)
end

function H:StepIssue(f, delta)
  local days = self:Issues()
  local target = days[IssueIndex(days, f.issueDay) + delta]
  if target then f.issueDay = target.day end
  self:Refresh()
end
