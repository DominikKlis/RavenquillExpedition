local ADDON, ns = ...
local GS = RavenquillExpedition
local H, News = ns.H, ns.News
local SafeCall, Plain = GS.SafeCall, GS.Plain
local T = GS.NewLocale(ns.NewsLocales)

H.MASTHEAD = "Interface\\AddOns\\RavenquillExpedition_Highlights\\Media\\masthead"
H.PARCHMENT = "Interface\\QuestFrame\\QuestBG"
H.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local MASTHEAD_FONT = "Fonts\\MORPHEUS.TTF"
local BASE_FONT = "Fonts\\FRIZQT__.TTF"
local INK, INK_SOFT, RULE, PAPER = { 0.17, 0.13, 0.09 }, { 0.36, 0.29, 0.22 }, { 0.48, 0.40, 0.29 }, { 0.92, 0.86, 0.72 }
local LABEL = { 0.85, 0.78, 0.62 }
local TIME_HEX = "6b5a45"
local PAD, PHOTO_W, GUTTER, LEFT_W, BRIEF_GAP = 16, 64, 16, 330, 24

local function BaseFont()
  local obj = GameFontHighlightSmall
  return Plain(obj and obj.GetFont and obj:GetFont(), "string") or BASE_FONT
end

local function Text(parent, size, opts)
  opts = opts or {}
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  if fs:SetFont(opts.file or BaseFont(), size, "") == false then fs:SetFontObject("GameFontHighlightSmall") end
  local c = opts.color or INK
  fs:SetTextColor(c[1], c[2], c[3])
  fs:SetShadowOffset(0, 0)
  fs:SetJustifyH(opts.justify or "LEFT")
  fs:SetJustifyV("TOP")
  if opts.lines then fs:SetMaxLines(opts.lines) end
  return fs
end

local function Below(region, anchor, gap, width)
  region:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
  if width then region:SetWidth(width) else region:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -gap) end
  return region
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
  t:SetPoint("TOPLEFT", PAD, y)
  t:SetPoint("TOPRIGHT", -PAD, y)
  return t
end

local function FileOK(path)
  if type(GetFileIDFromPath) ~= "function" then return true end
  local ok, id = pcall(GetFileIDFromPath, path)
  return ok and Plain(id) ~= nil
end

local function Parchment(paper)
  local bg = paper:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  local source = "color"
  if FileOK(H.PARCHMENT) and bg:SetTexture(H.PARCHMENT) ~= false then
    bg:SetTexCoord(0, 1, 0, 1)
    bg:SetVertexColor(1, 0.96, 0.86)
    source = "texture"
  else
    bg:SetColorTexture(PAPER[1], PAPER[2], PAPER[3], 1)
  end
  paper.parchment = { texture = bg, source = source }
end

local function Masthead(paper)
  local tex = paper:CreateTexture(nil, "ARTWORK")
  tex:SetSize(448, 56)
  tex:SetPoint("TOP", 0, -6)
  local result = tex:SetTexture(H.MASTHEAD)
  local fs = Text(paper, 30, { file = MASTHEAD_FONT, justify = "CENTER" })
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
  paper.metaLeft = Text(paper, 10, { color = INK_SOFT })
  paper.metaLeft:SetPoint("TOPLEFT", PAD, -74)
  paper.metaDate = Text(paper, 10, { color = INK_SOFT, justify = "CENTER" })
  paper.metaDate:SetPoint("TOP", 0, -74)
  paper.metaRight = Text(paper, 10, { color = INK_SOFT, justify = "RIGHT" })
  paper.metaRight:SetPoint("TOPRIGHT", -PAD, -74)
  return TopRule(paper, -89)
end

local function Photo(box)
  local frame = box:CreateTexture(nil, "BORDER")
  frame:SetColorTexture(0.11, 0.08, 0.05, 1)
  frame:SetSize(52, 52)
  frame:SetPoint("TOPLEFT", 2, 0)
  local icon = box:CreateTexture(nil, "ARTWORK")
  icon:SetSize(48, 48)
  icon:SetPoint("CENTER", frame, "CENTER")
  icon:SetDesaturated(true)
  icon:SetVertexColor(0.92, 0.80, 0.62)
  local caption = Text(box, 9, { color = INK_SOFT, justify = "CENTER", lines = 3 })
  caption:SetPoint("TOP", frame, "BOTTOM", 0, -3)
  caption:SetWidth(PHOTO_W - 4)
  return { icon = icon, caption = caption }
end

local function Lead(paper, rule, inner)
  local lead = {}
  lead.kicker = Text(paper, 10, { color = INK_SOFT, lines = 1 })
  lead.kicker:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -8)
  lead.kicker:SetPoint("TOPRIGHT", rule, "BOTTOMRIGHT", 0, -8)
  lead.head = Below(Text(paper, 20, { lines = 2 }), lead.kicker, 4)
  lead.dek = Below(Text(paper, 13, { color = INK_SOFT, lines = 2 }), lead.head, 5)
  lead.box = Below(CreateFrame("Frame", nil, paper), lead.dek, 8)
  lead.box:SetHeight(122)
  lead.photo = Photo(lead.box)
  lead.colW = (inner - PHOTO_W - GUTTER) / 2
  lead.col1 = Text(lead.box, 12, { lines = 8 })
  lead.col1:SetPoint("TOPLEFT", PHOTO_W, 0)
  lead.col2 = Text(lead.box, 12, { lines = 8 })
  lead.col2:SetPoint("TOPLEFT", lead.col1, "TOPRIGHT", GUTTER, 0)
  lead.col2:SetWidth(lead.colW)
  lead.colRule = Rule(lead.box, 1, 112)
  lead.colRule:SetPoint("TOPLEFT", lead.col1, "TOPRIGHT", GUTTER / 2, 0)
  paper.lead = lead
end

local function SecondRow(paper, inner)
  local box = paper.lead.box
  local top = Below(Rule(paper), box, 6)
  Below(Rule(paper), top, 2)
  local sec = {}
  sec.kicker = Below(Text(paper, 10, { color = INK_SOFT, lines = 1 }), top, 10, LEFT_W)
  sec.head = Below(Text(paper, 16, { lines = 2 }), sec.kicker, 4, LEFT_W)
  sec.body = Below(Text(paper, 12, { lines = 9 }), sec.head, 5, LEFT_W)
  local vrule = Rule(paper, 1, 200)
  vrule:SetPoint("TOPLEFT", top, "BOTTOMLEFT", LEFT_W + BRIEF_GAP / 2, -8)
  paper.second = sec
  local brief = { lines = {}, width = inner - LEFT_W - BRIEF_GAP }
  brief.title = Text(paper, 18, { file = MASTHEAD_FONT })
  brief.title:SetPoint("TOPLEFT", top, "BOTTOMLEFT", LEFT_W + BRIEF_GAP, -8)
  brief.title:SetText(T.IN_BRIEF)
  local prev = brief.title
  for i = 1, News.BRIEF_MAX do
    brief.lines[i] = Below(Text(paper, 11, { lines = 2 }), prev, 6, brief.width)
    prev = brief.lines[i]
  end
  brief.more = Text(paper, 10, { color = INK_SOFT, lines = 2 })
  brief.more:SetWidth(brief.width)
  paper.brief = brief
end

local function NavButtons(f)
  local function Button(text, width)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
  end
  f.prev = Button(T.PREV, 168)
  f.prev:SetPoint("BOTTOMLEFT", 16, 6)
  f.modeButton = Button(T.CHRONICLE, 90)
  f.modeButton:SetPoint("BOTTOMRIGHT", -16, 6)
  f.next = Button(T.NEXT, 168)
  f.next:SetPoint("RIGHT", f.modeButton, "LEFT", -10, 0)
  f.issueLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.issueLabel:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
  f.issueLabel:SetPoint("RIGHT", f.next, "LEFT", -4, 0)
  f.issueLabel:SetJustifyH("CENTER")
  f.issueLabel:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
  f.prev:SetScript("OnClick", function() GS:Call(H.StepIssue, H, f, -1) end)
  f.next:SetScript("OnClick", function() GS:Call(H.StepIssue, H, f, 1) end)
  f.modeButton:SetScript("OnClick", function() GS:Call(H.SetWindowMode, H, f.mode == "paper" and "log" or "paper") end)
end

function H:AttachPaper(f, insets)
  local paper = CreateFrame("Frame", nil, f)
  paper:SetPoint("TOPLEFT", insets[1], insets[2])
  paper:SetPoint("BOTTOMRIGHT", insets[3], insets[4])
  if paper.SetClipsChildren then paper:SetClipsChildren(true) end
  local inner = self.WINDOW_W - insets[1] + insets[3] - 2 * PAD
  Parchment(paper)
  Masthead(paper)
  Lead(paper, Meta(paper), inner)
  SecondRow(paper, inner)
  f.paper = paper
  NavButtons(f)
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
  local split = story.body[2] ~= nil
  lead.col1:SetWidth(split and lead.colW or 2 * lead.colW + GUTTER)
  lead.col1:SetText(story.body[1] or "")
  lead.col2:SetText(story.body[2] or "")
  lead.col2:SetShown(split)
  lead.colRule:SetShown(split)
  SetPhoto(lead.photo, story)
end

local function SetSecond(sec, story)
  sec.kicker:SetText(story and story.kicker or T.NO_SECOND_KICKER)
  sec.head:SetText(story and story.head or T.NO_SECOND_HEAD)
  sec.body:SetText(story and story.body[1] or T.NO_SECOND_BODY)
end

local function MoreText(issue)
  local extra = issue and issue.more or 0
  if extra > 0 then return News.Pick({ T.MORE_BRIEF }, "more", { n = News.Count(extra, T) }) end
  return (issue and issue.brief[1]) and "" or T.NO_BRIEF
end

local function SetBrief(brief, issue)
  local lines = issue and issue.brief or {}
  local last = brief.title
  for i, fs in ipairs(brief.lines) do
    local line = lines[i]
    fs:SetText(line and ("|cff%s%s|r  %s"):format(TIME_HEX, line.time, line.text) or "")
    fs:SetShown(line ~= nil)
    if line then last = fs end
  end
  brief.more:ClearAllPoints()
  Below(brief.more, last, 8, brief.width)
  brief.more:SetText(MoreText(issue))
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
end

local function IssueIndex(days, day)
  for i, rec in ipairs(days) do if rec.day == day then return i end end
  return #days
end

local function SetNav(f, i, n, issue)
  if i > 1 then f.prev:Enable() else f.prev:Disable() end
  if i < n then f.next:Enable() else f.next:Disable() end
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
