local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local NK = dofile(DEV .. "newskit.lua")
local Kit, Layout, At, E = NK.Kit, NK.Layout, NK.At, NK.E
local check = Kit.check

local ART = { left = 0.02, right = 0.58, top = 0.02, bottom = 0.65 }
local ATLAS = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V",
  "W", "X", "Y", "Z", "Ä", "Ö", "Ü" }

local function LayoutClient(name, locale, extra)
  return NK.Client(name, locale, function(env, c)
    Layout.Install(c)
    Layout.Pin(env.UIParent, 0, 0, 1920, 1080)
    c.frameMethods.SetDesaturated = function(s, on) s._desaturated = on end
    c.frameMethods.SetVertexColor = function(s, r, g, b) s._tint = { r, g, b } end
    if extra then extra(env, c) end
  end)
end

local function Heard(c, entries)
  for _, e in ipairs(entries) do c.H:Add(e, "wire") end
end

local BUSY_DAY = {
  E("boss", "Rika Steinbeck", At(20, 0, 23), { inst = "Dalaran", boss = "Atrexis der Grabritter", enc = 1 }),
  E("boss", "Rika Steinbeck", At(20, 0, 40), { inst = "Dalaran", boss = "Mortis", enc = 2 }),
  E("boss", "Rika Steinbeck", At(20, 1, 16), { inst = "Dalaran", boss = "Schemen des Erzmagiers", enc = 3 }),
  E("gear", "Hanne Moosgrund", At(20, 2, 49), { item = 5004, q = 3, il = 55, oil = 44, slot = 17 }),
  E("level", "Ole Fichtental", At(20, 1, 5), { lvl = 10 }),
  E("skill", "Ole Fichtental", At(20, 3, 11), { skill = "Alchemy", rank = 150 }),
  E("skill", "Ole Fichtental", At(20, 3, 13), { skill = "Leatherworking", rank = 150 }),
  E("quest", "Mira Sturmfeder", At(20, 9), { qid = 11, title = "Die Köpfe der Bande des Defias-Rudels", tag = "special" }),
  E("mount", "Tamo Eichengrund", At(20, 11), { lvl = 40 }),
  E("rep", "Bodo Kesselring", At(20, 12), { st = 7, fac = "Argentumdämmerung" }),
}

local function PaperTextures(c, paper)
  local out = {}
  for _, r in ipairs(c.regions) do
    if r._type == "Texture" and r._parent == paper and r._layer == "BACKGROUND" and r._shown then out[#out + 1] = r end
  end
  return out
end

local function OpaqueBase(c, paper)
  local pr = Layout.Rect(paper)
  for _, t in ipairs(PaperTextures(c, paper)) do
    local r = Layout.Rect(t)
    if t._color and t._color[4] == 1 and (t._alpha or 1) == 1 and r and Layout.Inside(r, pr) then return t, r end
  end
end

local function Grain(c, paper, file)
  for _, t in ipairs(PaperTextures(c, paper)) do if t._file == file then return t end end
end

local function TextsOff(c, paper, rect)
  local off = {}
  for _, fs in ipairs(Layout.Texts(c, paper)) do
    local r = Layout.Rect(fs)
    if not (r and Layout.Inside(rect, r)) then off[#off + 1] = fs._text:sub(1, 40) end
  end
  return off
end

local function CropInsideArt(tc)
  return tc and tc[1] >= ART.left and tc[2] <= ART.right and tc[3] >= ART.top and tc[4] <= ART.bottom and tc[1] < tc[2]
    and tc[3] < tc[4]
end

Kit.section("Paper: an opaque paper-coloured base covers the whole page, under every text, with a vignette over the grain")
do
  local c = LayoutClient("Lyra Distelbach")
  Heard(c, BUSY_DAY)
  c.H:ShowWindow()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  local paper = f.paper
  local base, rect = OpaqueBase(c, paper)
  check(base ~= nil, "the page has an opaque colour base the size of the whole page")
  local texts = Layout.Texts(c, paper)
  local off = base and TextsOff(c, paper, rect) or { "no base" }
  check(#texts >= 16 and #off == 0, "all " .. #texts .. " text regions sit on that base (" .. (off[1] or "none off") .. ")")
  local grain = Grain(c, paper, c.H.PARCHMENT)
  check(grain and CropInsideArt(grain._tc) and (grain._alpha or 1) < 1 and grain._sublevel > base._sublevel,
    "the parchment art is cropped to its clean middle, translucent, drawn over the base")
  local vignette = Grain(c, paper, c.H.VIGNETTE)
  check(vignette and vignette._sublevel > grain._sublevel and Layout.Inside(Layout.Rect(vignette), Layout.Rect(paper))
    and Layout.Inside(Layout.Rect(paper), Layout.Rect(vignette)), "the vignette lies over the grain and covers the whole page")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.section("Paper: without the parchment file the page is still fully paper-coloured")
do
  local c = LayoutClient("Tamo Eichengrund", "deDE", function(env) env.GetFileIDFromPath = function() return nil end end)
  Heard(c, BUSY_DAY)
  c.H:ShowWindow()
  local paper = c.env.RavenquillExpeditionHighlightsFrame.paper
  local base, rect = OpaqueBase(c, paper)
  check(base ~= nil and #TextsOff(c, paper, rect) == 0 and not Grain(c, paper, c.H.PARCHMENT),
    "a missing parchment file leaves the plain paper base, no grain")
  check(paper.parchment.source == "color", "the smoke test sees the colour source")
end

local function Offenders(c, paper)
  local pr, out = Layout.Rect(paper), {}
  for _, fs in ipairs(Layout.Texts(c, paper)) do
    local r = Layout.Rect(fs)
    if not (r and Layout.Inside(pr, r)) or Layout.Truncated(fs) then out[#out + 1] = fs._text:sub(1, 50) end
  end
  return out
end

local function Squash(s) return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

local function SentencePrefix(shown, full)
  if shown == "" then return true end
  local after = full:sub(#shown + 1, #shown + 1)
  return full:sub(1, #shown) == shown and shown:find("[%.!?]$") ~= nil and (after == "" or after:find("%s") ~= nil)
end

local function WholeUnits(text, paragraphs)
  text = Squash(text)
  for n = 1, #paragraphs do if text == Squash(table.concat(paragraphs, "\n", 1, n)) then return true end end
  return SentencePrefix(text, Squash(paragraphs[1] or ""))
end

local function LeadText(lead)
  local letter = lead.cap:IsShown() and lead.cap.letter or ""
  return Squash(letter .. (lead.beside:GetText() or "") .. " " .. (lead.rest:GetText() or ""))
end

local function Cut(paper)
  local issue = paper.issue
  local second = paper.second.body:GetText() or ""
  local checks = { { second, issue.second and issue.second.body or { second } }, { LeadText(paper.lead), issue.lead.body } }
  if paper.third.body:IsShown() then checks[3] = { paper.third.body:GetText(), issue.extra[1].body } end
  for _, pair in ipairs(checks) do
    if not WholeUnits(pair[1], pair[2]) then return pair[1] end
  end
end

local function ShownBrief(paper)
  local n = 0
  for _, fs in ipairs(paper.brief.lines) do if fs:IsShown() then n = n + 1 end end
  return n
end

local function ThirdShown(paper) return paper.third.head:IsShown() and paper.third.body:IsShown() and 1 or 0 end

local function OpenSized(c, w, h)
  c.H.WINDOW_W, c.H.WINDOW_H = w, h
  c.H:ShowWindow()
  c.H:Refresh()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  return f, f.paper
end

local function R(region) return Layout.Rect(region) end

local function MainRight(paper)
  local right = 0
  for _, fs in ipairs({ paper.lead.head, paper.lead.dek, paper.lead.rest, paper.lead.beside, paper.second.body, paper.third.body }) do
    if fs:IsShown() and (fs:GetText() or "") ~= "" then right = math.max(right, R(fs).right) end
  end
  return right
end

local function SidebarRight(paper)
  local main, left = MainRight(paper), math.huge
  for _, fs in ipairs(paper.brief.lines) do if fs:IsShown() then left = math.min(left, R(fs).left) end end
  local rule = R(paper.sideRule)
  return left > main and rule.left > main and rule.right < left and rule.height > rule.width
end

local function SideBySide(paper)
  local sec, third = paper.second, paper.third
  local s, t, rule = R(sec.head), R(third.head), R(paper.pairColumnRule)
  return t.top == s.top and R(third.kicker).left > R(sec.body).right and rule.left > R(sec.body).right
    and rule.right < t.left and R(paper.pairRule).top > R(sec.kicker).top and R(paper.pairRule).bottom < R(paper.lead.photo.frame).bottom
end

Kit.section("Paper: every text sits fully on the page, nothing is cut mid-sentence")
do
  local c = LayoutClient("Lyra Distelbach")
  Heard(c, BUSY_DAY)
  local f, paper = OpenSized(c, 640, 640)
  local off = Offenders(c, paper)
  check(#off == 0, "in the window every text is on the page and shown in full (" .. (off[1] or "none") .. ")")
  check(Cut(paper) == nil and LeadText(paper.lead) == Squash(table.concat(paper.issue.lead.body, " ")),
    "the window has room for the whole lead story (" .. LeadText(paper.lead) .. ")")
  check(ThirdShown(paper) == 1 and ShownBrief(paper) + 1 == #paper.issue.brief and SideBySide(paper),
    "the third story stands beside the second, every other report fits in the brief")
  f:Hide()
  f, paper = OpenSized(c, 640, 470)
  off = Offenders(c, paper)
  check(#off == 0, "in a short window every text still stays on the page (" .. (off[1] or "none") .. ")")
  local cut = Cut(paper)
  check(cut == nil, "bodies keep whole paragraphs or whole sentences, never a cut one (" .. tostring(cut) .. ")")
  f:Hide()
  _, paper = OpenSized(c, 640, 395)
  off, cut = Offenders(c, paper), Cut(paper)
  local shortened = LeadText(paper.lead) ~= Squash(table.concat(paper.issue.lead.body, " "))
    or paper.second.body:GetText() ~= table.concat(paper.issue.second.body, "\n")
  check(#off == 0 and cut == nil and shortened, "a very short page drops whole paragraphs, then whole sentences, and keeps "
    .. "everything on the page (" .. (off[1] or tostring(cut)) .. ")")
  local dropped = #paper.issue.brief - ShownBrief(paper) - ThirdShown(paper)
  local more = paper.brief.more:GetText() or ""
  check(dropped > 0 and more:lower():find(c.ns[NK.HL].News.Count(paper.issue.more + dropped, c.ns[NK.HL].NewsLocales.deDE), 1, true),
    "brief lines that do not fit are dropped whole and counted in the line about the chronicle (" .. more .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

local function Click(b) b:GetScript("OnClick")(b) end

local function Bottom(c, paper)
  local low = math.huge
  for _, fs in ipairs(Layout.Texts(c, paper)) do low = math.min(low, Layout.Rect(fs).bottom) end
  return low
end

local function Boxed(ear, ink)
  local lines, text = ear.lines, R(ear.top)
  local box = { left = R(lines[3]).left, right = R(lines[4]).right, top = R(lines[1]).top, bottom = R(lines[2]).bottom }
  return Layout.Inside(box, text) and Layout.Inside(box, R(ear.bottom)) and R(lines[1]).height == 1 and R(lines[3]).width == 1
    and lines[1]._color[1] == ink[1] and lines[4]._color[3] == ink[3]
end

local function Ears(paper, mast)
  local left, right = paper.ears[1], paper.ears[2]
  local l, r, m = R(left.lines[4]), R(right.lines[3]), R(mast)
  local mid = (m.top + m.bottom) / 2
  return l.right < m.left and r.left > m.right and l.top > mid and l.bottom < mid and r.top > mid and r.bottom < mid
end

local function DoubleRule(rules, upper, lower)
  local thin, thick = R(rules.thin), R(rules.thick)
  return thin.height == 1 and thick.height == 2 and thick.top < thin.bottom and thin.bottom - thick.top <= 4
    and thin.width == thick.width and thin.top < upper and thick.bottom > lower
end

Kit.section("Masthead: Rabenblatt between two boxed ears, a double rule, then the paper's name and the date")
do
  local c = LayoutClient("Lyra Distelbach")
  Heard(c, BUSY_DAY)
  c.H:ShowWindow()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  local paper = f.paper
  local ears = paper.ears
  check(ears[1].top:GetText() == "Nr. 1" and ears[1].bottom:GetText() == "Freitag" and ears[2].top:GetText() == "Preis"
    and ears[2].bottom:GetText() == "1 Kupfer", "the left ear holds the issue number and weekday, the right one the price")
  check(Boxed(ears[1], c.H.INK_SOFT) and Boxed(ears[2], c.H.INK_SOFT) and Ears(paper, paper.masthead.texture),
    "each ear sits in a 1 px ink-soft box beside the masthead, level with its middle")
  check(paper.metaLeft:GetText() == "Gildenblatt der Ravenquill Expedition" and paper.metaDate:GetText() == "20. November"
    and R(paper.metaDate).left > R(paper.metaLeft).right and math.abs(R(paper.metaDate).right - R(paper.mastRules.thin).right) < 0.5,
    "under it the paper's name on the left, the date without weekday on the right")
  check(DoubleRule(paper.mastRules, R(paper.masthead.texture).bottom + 0.5, R(paper.metaLeft).top),
    "a thin and a thick rule run between the masthead and that line")
  check(paper.masthead.texture._file == c.H.MASTHEAD and not paper.masthead.text:IsShown(), "the masthead is the texture")
  local en = LayoutClient("Mira Sturmfeder", "enUS")
  Heard(en, BUSY_DAY)
  en.H:ShowWindow()
  local ep = en.env.RavenquillExpeditionHighlightsFrame.paper
  check(ep.ears[1].top:GetText() == "No. 1" and ep.ears[1].bottom:GetText() == "Friday" and ep.ears[2].top:GetText() == "Price"
    and ep.ears[2].bottom:GetText() == "1 copper" and ep.metaDate:GetText() == "November 20", "English ears and date")
  check(ep.brief.title.texture._file:find("inbrief_enUS", 1, true) and paper.brief.title.texture._file:find("inbrief_deDE", 1, true),
    "In Kürze and In Brief are each language's own blackletter heading")
  check(#c.errors == 0 and #en.errors == 0, "no Lua errors (" .. tostring(c.errors[1] or en.errors[1]) .. ")")
end

local function DotsUnder(paper)
  local brief = paper.brief
  for i, fs in ipairs(brief.lines) do
    local dots = brief.dots[i]
    if fs:IsShown() ~= dots:IsShown() then return false end
    if fs:IsShown() then
      local d, nextLine = R(dots), brief.lines[i + 1]
      if d.top > R(fs).bottom or dots._file ~= paper.dotsFile or d.width ~= R(fs).width then return false end
      if nextLine and nextLine:IsShown() and R(nextLine).top > d.bottom then return false end
    end
  end
  return true
end

local function Woodcut(H, photo, size)
  local frame, icon = R(photo.frame), R(photo.icon)
  local tint = photo.icon._tint
  local ink = photo.frame._color
  return frame.width == size and frame.height == size and icon.left - frame.left == 3 and frame.right - icon.right == 3
    and frame.top - icon.top == 3 and icon.bottom - frame.bottom == 3 and photo.icon._desaturated == true
    and tint[1] > tint[2] and tint[2] > tint[3] and ink[1] == H.INK[1] and ink[4] == 1
end

Kit.section("Grid: lead with woodcut and drop cap, two stories side by side, In Kürze as a sidebar")
do
  local c = LayoutClient("Lyra Distelbach")
  Heard(c, BUSY_DAY)
  c.H:ShowWindow()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  local paper = f.paper
  paper.dotsFile = c.H.DOTTED
  local lead = paper.lead
  check(lead.kicker:GetText() == c.H.Upper(paper.issue.lead.kicker) and lead.kicker:GetText():find("^%u"),
    "the lead's kicker is set in capitals (" .. lead.kicker:GetText() .. ")")
  check(Woodcut(c.H, lead.photo, 100), "the woodcut is the icon at 100 px in a 3 px ink frame, desaturated and tinted brown")
  local cap, frame = R(lead.photo.caption), R(lead.photo.frame)
  check(lead.photo.caption:GetText() == paper.issue.lead.caption and cap.top <= frame.bottom
    and math.abs((cap.left + cap.right) / 2 - (frame.left + frame.right) / 2) < 0.5, "its caption is centred under it")
  check(R(lead.beside).left > frame.right and R(lead.rest).left > frame.right, "the lead body runs right of the woodcut")
  check(SideBySide(paper) and paper.third.head:GetText() == paper.issue.extra[1].head
    and paper.third.kicker:GetText() == c.H.Upper(paper.issue.extra[1].kicker),
    "the second and third stories stand side by side under a rule, a rule between them")
  check(SidebarRight(paper), "In Kürze is a sidebar right of the stories, behind a vertical rule")
  local title, art = R(paper.brief.title.texture), R(paper.brief.underline)
  check(paper.brief.title.loaded and math.abs((title.left + title.right) / 2 - (art.left + art.right) / 2) < 0.5
    and art.top <= title.bottom and art.width < R(paper.brief.lines[1]).width / 2,
    "its blackletter heading is centred, a short rule under it")
  check(DotsUnder(paper) and ShownBrief(paper) == #paper.issue.brief - 1,
    "a dotted rule runs under every brief item; the fourth story and the rest are in the brief")
  local twice = nil
  for _, line in ipairs(paper.brief.lines) do
    if line:IsShown() and line:GetText():find(paper.third.head:GetText(), 1, true) then twice = line:GetText() end
  end
  check(twice == nil, "no story is told twice (" .. tostring(twice) .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

local function EmptyPaper(locale, body)
  local c = LayoutClient("Ilka Dornbusch", locale)
  if body then c.ns[NK.HL].NewsLocales[locale].EMPTY_BODY = body end
  c.H:ShowWindow()
  return c, c.env.RavenquillExpeditionHighlightsFrame.paper
end

local function CapCell(letter)
  for i, l in ipairs(ATLAS) do
    if l == letter then return (i - 1) % 8 / 8, math.floor((i - 1) / 8) / 4 end
  end
end

local function DropCapShown(lead, letter, body)
  local cap, beside, rest = R(lead.cap), R(lead.beside), R(lead.rest)
  local col, row = CapCell(letter)
  local tc, lines = lead.cap._tc, 3 * lead.beside._fontSize * Layout.LINE_EM
  return lead.cap:IsShown() and lead.cap.letter == letter and lead.cap._file:find("dropcaps", 1, true) and tc[1] == col
    and tc[3] == row and tc[4] == row + 0.25 and tc[2] > tc[1] and math.abs(cap.height - lines) < 0.5
    and beside.left >= cap.right and beside.top == cap.top and rest.top <= cap.bottom and rest.left == cap.left
    and (lead.beside:GetText() or ""):sub(1, 3) == body:sub(#letter + 1, #letter + 3)
end

Kit.section("Drop cap: the lead body opens with a blackletter capital when its first letter is in the atlas")
do
  local c, paper = EmptyPaper("deDE")
  local DE = c.ns[NK.HL].NewsLocales.deDE
  check(DropCapShown(paper.lead, "W", DE.EMPTY_BODY) and LeadText(paper.lead) == Squash(DE.EMPTY_BODY .. " " .. DE.EMPTY_MORE),
    "a body starting with W gets the W cut from the atlas, three lines high, the text beside and under it reads on whole")
  local _, umlaut = EmptyPaper("deDE", "Ärger gab es heute keinen. Die Redaktion meldet einen ruhigen Abend in der Gildenhalle "
    .. "und bittet um mehr Abenteuer.")
  check(DropCapShown(umlaut.lead, "Ä", "Ärger gab"), "an umlaut capital comes from its own cell")
  local quote = "„Ruhe“, meldet die Redaktion. Es gab heute nichts zu berichten."
  local _, quoted = EmptyPaper("deDE", quote)
  check(not quoted.lead.cap:IsShown() and quoted.lead.rest:GetText():find(quote, 1, true) == 1
    and R(quoted.lead.rest).top == R(quoted.lead.photo.frame).top, "a body opening with a quote mark gets no drop cap, the text starts in full")
  local _, digit = EmptyPaper("enUS", "1000 thanks to the guild. Nothing else happened today.")
  check(not digit.lead.cap:IsShown() and digit.lead.rest:GetText():sub(1, 4) == "1000", "nor does one opening with a digit")
  local _, missing = EmptyPaper("deDE")
  missing.lead.cap.loaded = false
  missing:GetScript("OnSizeChanged")()
  check(not missing.lead.cap:IsShown() and missing.lead.rest:GetText():sub(1, 3) == "Was", "without the atlas there is no drop cap")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.section("Window: 900 wide, at most 780 high and 90% of the screen, sized to the issue, smaller type on a small screen")
do
  local c = LayoutClient("Lyra Distelbach")
  Heard(c, BUSY_DAY)
  c.H:ShowWindow()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  local r = Layout.Rect(f)
  local gap = Bottom(c, f.paper) - Layout.Rect(f.prev).top
  check(r.width == 900 and r.height <= 780 and r.height >= c.H.WINDOW_MIN_H and gap >= 0 and gap < 60,
    ("on a 1920x1080 screen the sheet is 900 wide and ends just under its last text (%.0fx%.0f, %.0f px spare)"):format(r.width,
      r.height, gap))
  local off, cut = Offenders(c, f.paper), Cut(f.paper)
  check(#off == 0 and cut == nil, "every text on the paper, none cut (" .. (off[1] or tostring(cut)) .. ")")
  check(ThirdShown(f.paper) == 1 and ShownBrief(f.paper) + 1 == #f.paper.issue.brief,
    "a busy day fills the page: a third story beside the second, every other report in the brief")
  local quiet = LayoutClient("Mira Sturmfeder")
  Heard(quiet, { E("level", "Bodo Kesselring", At(20, 10), { lvl = 20 }), E("mount", "Tamo Eichengrund", At(20, 11), { lvl = 40 }) })
  quiet.H:ShowWindow()
  local qf = quiet.env.RavenquillExpeditionHighlightsFrame
  local qr = Layout.Rect(qf)
  check(qr.width == 900 and qr.height < r.height and qr.height >= quiet.H.WINDOW_MIN_H and #Offenders(quiet, qf.paper) == 0
    and Cut(qf.paper) == nil, ("a quiet day gives a shorter sheet, nothing cut (%.0fx%.0f against %.0f)"):format(qr.width, qr.height,
      r.height))
  check(not qf.paper.third.head:IsShown() and R(qf.paper.second.body).right > R(qf.paper.lead.beside).left,
    "without a third story the second one takes the whole width of the main column")
  local long = LayoutClient("Mira Sturmfeder")
  for i, boss in ipairs({ "Schlingwurzler", "Noxxion", "Celebras der Verfluchte", "Erdrutsch", "Prinzessin Theradras", "Faulschnapper" }) do
    Heard(long, { E("boss", "Bodo Kesselring", At(20, 18, 20) + i * 400, { inst = "Maraudon", boss = boss, first = true, lvl = 52 }) })
  end
  local _, lpaper = OpenSized(long, 640, 640)
  local lp = lpaper.lead
  check(lp.cap:IsShown() and R(lp.rest).left == R(lp.cap).left and (lp.rest:GetText() or "") ~= "" and #Offenders(long, lpaper) == 0
    and Cut(lpaper) == nil, "a long lead story wraps beside the drop cap and runs on under it, whole sentences only")
  local small = LayoutClient("Tamo Eichengrund", "deDE", function(env) Layout.Pin(env.UIParent, 0, 0, 1024, 600) end)
  Heard(small, BUSY_DAY)
  small.H:ShowWindow()
  local sf = small.env.RavenquillExpeditionHighlightsFrame
  local sr = Layout.Rect(sf)
  check(sr.width == 900 and sr.height <= 540, ("on a 1024x600 screen the window keeps to 90%% of the height (%dx%d)"):format(sr.width,
    sr.height))
  check(#Offenders(small, sf.paper) == 0 and Cut(sf.paper) == nil, "there too every text sits on the paper, none cut")
  local lead, low = f.paper.lead, sf.paper.lead
  sf.paper.dotsFile = small.H.DOTTED
  check(low.head._fontSize < lead.head._fontSize and low.rest._fontSize < lead.rest._fontSize and Woodcut(small.H, low.photo, 68)
    and low.cap:IsShown() and SidebarRight(sf.paper) and DotsUnder(sf.paper) and SideBySide(sf.paper),
    ("there the same parts come smaller: headline and body %d/%d against %d/%d, a 68 px woodcut"):format(low.head._fontSize,
      low.rest._fontSize, lead.head._fontSize, lead.rest._fontSize))
  check(#c.errors == 0 and #small.errors == 0, "no Lua errors (" .. tostring(c.errors[1] or small.errors[1]) .. ")")
end

local function InkClient()
  local templates = {}
  local c = LayoutClient("Lyra Distelbach", "deDE", function(env, cl)
    local create = env.CreateFrame
    env.CreateFrame = function(otype, name, parent, template)
      local f = create(otype, name, parent, template)
      templates[f] = template or false
      return f
    end
    cl.frameMethods.SetTextColor = function(s, r, g, b) s._ink = { r, g, b } end
  end)
  return c, templates
end

local function ShadowSides(c, f)
  local fr, sides = Layout.Rect(f), {}
  for _, r in ipairs(c.regions) do
    local col, rect = r._color, r._type == "Texture" and r._parent == f and Layout.Rect(r)
    if rect and col and col[1] == 0 and col[2] == 0 and col[3] == 0 and col[4] < 1 then
      if rect.right <= fr.left then sides.left = true end
      if rect.left >= fr.right then sides.right = true end
      if rect.bottom >= fr.top then sides.top = true end
      if rect.top <= fr.bottom then sides.bottom = true end
    end
  end
  return sides.left and sides.right and sides.top and sides.bottom
end

local function Darker(a, b) return a[1] + a[2] + a[3] < b[1] + b[2] + b[3] end

local function InkFooter(f)
  for _, b in ipairs({ f.prev, f.next, f.chronicle }) do
    if not (b.label and b.underline and b.label._ink) then return false end
  end
  return true
end

local function Linked(b) return b:IsEnabled() and b.underline:IsShown() end

Kit.section("Paper: the woodcut's caption is never cut")
do
  local function CaptionOf(inst, bosses)
    local c = LayoutClient("Lyra Distelbach")
    for i, name in ipairs(bosses) do
      Heard(c, { E("boss", "Jori Wolkenfeld", At(20, 1, 5) + i * 300, { inst = inst, boss = name, enc = i, first = true }) })
    end
    c.H:ShowWindow()
    local cap = c.env.RavenquillExpeditionHighlightsFrame.paper.lead.photo.caption
    return c, cap
  end
  local c, cap = CaptionOf("Scharlachrotes Kloster", { "Herod", "Mograine", "Whitemane" })
  local text = cap:IsShown() and cap:GetText() or ""
  check(text:find("Scharlachrotes", 1, true) and not Layout.Truncated(cap),
    "a long word that fits the woodcut's width stays whole in the caption (" .. text .. ")")
  local long = select(2, CaptionOf("Schattenfangfestungsruinenkeller", { "Herod", "Mograine", "Whitemane" }))
  local longText = long:IsShown() and long:GetText() or ""
  check(not longText:find("Schattenfang", 1, true) and not Layout.Truncated(long),
    "a caption that cannot fit under the woodcut is replaced by one that fits, or left out (" .. longText .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.section("Window: a frameless sheet of paper with a soft shadow, an inked close mark and an inked footer")
do
  local c, templates = InkClient()
  Heard(c, BUSY_DAY)
  Heard(c, { E("level", "Bodo Kesselring", At(18, 10), { lvl = 20 }) })
  c.H:ShowWindow()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  local fr, pr = Layout.Rect(f), Layout.Rect(f.paper)
  check(templates[f] == false and not rawget(f, "NineSlice") and not rawget(f, "CloseButton") and not rawget(f, "portrait"),
    "the window is a plain frame: no template, no portrait, no title bar")
  check(OpaqueBase(c, f) ~= nil and pr.left == fr.left and pr.right == fr.right and pr.top == fr.top and pr.bottom == fr.bottom,
    "the whole window is paper: its own paper base and the newspaper cover it edge to edge")
  check(ShadowSides(c, f), "translucent black shadow strips lie outside the sheet on all four sides")
  local inUI = false
  for _, name in ipairs(c.env.UISpecialFrames) do inUI = inUI or name == "RavenquillExpeditionHighlightsFrame" end
  check(inUI and rawget(f, "_scripts").OnDragStart ~= nil, "Esc closes the sheet and it can be dragged")
  local close = f.close
  local cr = Layout.Rect(close)
  check(close:GetText() == "×" and templates[close] == false and cr.right <= fr.right and cr.top <= fr.top
    and cr.left > fr.left + fr.width * 0.9 and cr.bottom > fr.top - 40 and not close.underline:IsShown(),
    "a small inked × sits at the paper's top right, not underlined")
  check(cr.left > R(f.paper.ears[2].lines[4]).right or cr.bottom > R(f.paper.ears[2].lines[1]).top,
    "the × keeps clear of the price ear")
  local off = Offenders(c, f.paper)
  local lowest = Bottom(c, f.paper)
  check(#off == 0 and Cut(f.paper) == nil and lowest >= Layout.Rect(f.prev).top,
    "every text of the issue stays on the paper, above the footer (" .. (off[1] or "none") .. ")")
  check(DoubleRule(f.footerRules, lowest, R(f.prev).top), "a thin and a thick rule run between the issue and the footer")
  check(InkFooter(f) and templates[f.prev] == false and templates[f.chronicle] == false and f.prev:GetText() == "« VORHERIGE AUSGABE"
    and f.next:GetText() == "NÄCHSTE AUSGABE »" and f.chronicle:GetText() == "CHRONIK"
    and f.issueLabel:GetText() == "Ausgabe vom 20. November", "the footer links are printed in ink capitals: no red buttons")
  check(not f.next:IsEnabled() and not f.next.underline:IsShown() and Linked(f.prev) and Linked(f.chronicle)
    and Darker(f.prev.label._ink, f.next.label._ink), "on the newest issue the live links are underlined, 'Nächste Ausgabe' is greyed")
  check(R(f.prev).width >= utf8.len("« VORHERIGE AUSGABE") * 12 * Layout.CHAR_EM - 0.5, "each link is as wide as its words")
  local idle = f.prev.label._ink
  f.prev:GetScript("OnEnter")(f.prev)
  check(Darker(f.prev.label._ink, idle) and f.prev.underline:IsShown(), "hovering a link darkens it")
  f.prev:GetScript("OnLeave")(f.prev)
  check(f.prev.underline:IsShown() and not Darker(f.prev.label._ink, idle), "leaving it gives back the plain ink")
  Click(f.prev)
  check(f.issueLabel:GetText() == "Ausgabe vom 18. November" and Linked(f.next) and not f.prev:IsEnabled()
    and not f.prev.underline:IsShown() and Darker(f.next.label._ink, f.prev.label._ink),
    "the links page back an issue, and the greyed one follows")
  Click(f.next)
  check(f.issueLabel:GetText() == "Ausgabe vom 20. November", "and forward again")
  check(f.msg == nil and f.logPanel == nil, "the sheet holds the newspaper only: no log and no dark log panel")
  Click(f.chronicle)
  local page = c.env.RavenquillExpeditionOverview.optView.pages.Highlights
  check(not f:IsShown() and c.env.RavenquillExpedition.optionsModule == "Highlights" and page:IsShown() and page.msg ~= nil,
    "CHRONIK closes the sheet and opens the Chronik in the /rq Highlights tab")
  c.H:ShowWindow()
  Click(close)
  check(not f:IsShown(), "the × closes the sheet")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.finish()
