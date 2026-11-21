local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local NK = dofile(DEV .. "newskit.lua")
local Kit, Layout, At, E = NK.Kit, NK.Layout, NK.At, NK.E
local check = Kit.check

local ART = { left = 0.02, right = 0.58, top = 0.02, bottom = 0.65 }

local function LayoutClient(name, locale, extra)
  return NK.Client(name, locale, function(env, c)
    Layout.Install(c)
    Layout.Pin(env.UIParent, 0, 0, 1920, 1080)
    if extra then extra(env, c) end
  end)
end

local function Heard(c, entries)
  for _, e in ipairs(entries) do c.H:Add(e, "wire") end
end

local BUSY_DAY = {
  E("boss", "Fantastic Frank", At(20, 0, 23), { inst = "Dalaran", boss = "Atrexis der Grabritter", enc = 1 }),
  E("boss", "Fantastic Frank", At(20, 0, 40), { inst = "Dalaran", boss = "Mortis", enc = 2 }),
  E("boss", "Fantastic Frank", At(20, 1, 16), { inst = "Dalaran", boss = "Schemen des Erzmagiers", enc = 3 }),
  E("gear", "Faro Berangias", At(20, 2, 49), { item = 5004, q = 3, il = 55, oil = 44, slot = 17 }),
  E("level", "Daesha Tandaryel", At(20, 1, 5), { lvl = 10 }),
  E("skill", "Daesha Tandaryel", At(20, 3, 11), { skill = "Alchemy", rank = 150 }),
  E("skill", "Daesha Tandaryel", At(20, 3, 13), { skill = "Leatherworking", rank = 150 }),
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

Kit.section("Paper: an opaque paper-coloured base covers the whole page, under every text")
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

local function SentencePrefix(shown, full)
  if shown == "" then return true end
  local after = full:sub(#shown + 1, #shown + 1)
  return full:sub(1, #shown) == shown and shown:find("[%.!?]$") ~= nil and (after == "" or after:find("%s") ~= nil)
end

local function WholeUnits(text, paragraphs)
  for n = 1, #paragraphs do if text == table.concat(paragraphs, "\n", 1, n) then return true end end
  return SentencePrefix(text, paragraphs[1] or "")
end

local function LeadCut(paper)
  local lead, body = paper.lead, paper.issue.lead.body
  if not lead.col2:IsShown() then return not WholeUnits(lead.col1:GetText() or "", body) and lead.col1:GetText() end
  local shown = (lead.col1:GetText() or "") .. " " .. (lead.col2:GetText() or "")
  return not SentencePrefix(shown, table.concat(body, " ")) and shown
end

local function Cut(paper)
  local text = paper.second.body:GetText() or ""
  if not WholeUnits(text, paper.issue.second.body) then return text end
  return LeadCut(paper) or nil
end

local function Balanced(lead)
  local h1, h2 = lead.col1:GetStringHeight(), lead.col2:GetStringHeight()
  return math.abs(h1 - h2) <= lead.col1._fontSize * NK.Layout.LINE_EM + 0.5
end

local function ShownBrief(paper)
  local n = 0
  for _, fs in ipairs(paper.brief.lines) do if fs:IsShown() then n = n + 1 end end
  return n
end

local function OpenSized(c, w, h)
  local f = c.env.RavenquillExpeditionHighlightsFrame
  if f then f:SetSize(w, h) end
  c.H:ShowWindow()
  f = c.env.RavenquillExpeditionHighlightsFrame
  f:SetSize(w, h)
  c.H:Refresh()
  return f, f.paper
end

Kit.section("Paper: every text sits fully on the page, nothing is cut mid-sentence")
do
  local c = LayoutClient("Lyra Distelbach")
  Heard(c, BUSY_DAY)
  local f, paper = OpenSized(c, 640, 640)
  local off = Offenders(c, paper)
  check(#off == 0, "in the window every text is on the page and shown in full (" .. (off[1] or "none") .. ")")
  check(Cut(paper) == nil and paper.second.body:GetText() == table.concat(paper.issue.second.body, "\n"),
    "the window has room for both paragraphs of the second story (" .. tostring(paper.second.body:GetText()) .. ")")
  check(paper.lead.col2:IsShown() and paper.lead.col1:GetText() .. " " .. paper.lead.col2:GetText()
    == table.concat(paper.issue.lead.body, " ") and Balanced(paper.lead),
    "the lead body runs in two balanced columns, split between sentences")
  check(ShownBrief(paper) == #paper.issue.brief, "every brief line fits in the window")
  f:Hide()
  f, paper = OpenSized(c, 640, 470)
  off = Offenders(c, paper)
  check(#off == 0, "in a short window every text still stays on the page (" .. (off[1] or "none") .. ")")
  local cut = Cut(paper)
  check(cut == nil, "bodies keep whole paragraphs or whole sentences, never a cut one (" .. tostring(cut) .. ")")
  local dropped = #paper.issue.brief - ShownBrief(paper)
  local more = paper.brief.more:GetText() or ""
  check(dropped > 0 and more:lower():find(c.ns[NK.HL].News.Count(paper.issue.more + dropped, c.ns[NK.HL].NewsLocales.deDE), 1, true),
    "brief lines that do not fit are dropped whole and counted in the line about the chronicle (" .. more .. ")")
  f:Hide()
  f, paper = OpenSized(c, 640, 430)
  off, cut = Offenders(c, paper), Cut(paper)
  local shortened = paper.lead.col1:GetText() ~= paper.issue.lead.body[1]
    or paper.second.body:GetText() ~= table.concat(paper.issue.second.body, "\n")
  check(#off == 0 and cut == nil and shortened, "a very short page drops whole paragraphs, then whole sentences, and keeps "
    .. "everything on the page (" .. (off[1] or tostring(cut)) .. ")")
  f:Hide()
  _, paper = OpenSized(c, 460, 640)
  off = Offenders(c, paper)
  check(#off == 0 and not paper.lead.col2:IsShown() and paper.lead.col1:GetText():find(paper.issue.lead.body[1], 1, true),
    "a narrow page sets the lead body in one column, everything on the page (" .. (off[1] or "none") .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

local PAGE_W, PAGE_H = 632, 480

local function Click(b) b:GetScript("OnClick")(b) end

local function OpenTab(c, w, h)
  local GS = c.env.RavenquillExpedition
  GS:ShowModulePage("Highlights")
  local opt = c.env.RavenquillExpeditionOverview.optView
  Layout.Pin(opt.body, 100, 100, w, h)
  c.H:Refresh()
  return opt.pages.Highlights, opt
end

local function Below(upper, lower) return Layout.Rect(lower).top <= Layout.Rect(upper).bottom + 0.5 end

Kit.section("Window: 900x780 by default, at most 90% of the screen, larger type than the tab")
do
  local c = LayoutClient("Lyra Distelbach")
  Heard(c, BUSY_DAY)
  c.H:ShowWindow()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  local r = Layout.Rect(f)
  check(r.width == 900 and r.height == 780, ("on a 1920x1080 screen the window opens at 900x780 (%dx%d)"):format(r.width, r.height))
  local off, cut = Offenders(c, f.paper), Cut(f.paper)
  check(#off == 0 and cut == nil, "every text on the paper, none cut (" .. (off[1] or tostring(cut)) .. ")")
  check(f.paper.lead.col2:IsShown() and ShownBrief(f.paper) == #f.paper.issue.brief, "two lead columns and every brief line")
  local page = OpenTab(c, PAGE_W, PAGE_H)
  local lead, tab = f.paper.lead, page.paper.lead
  check(lead.head._fontSize > tab.head._fontSize and lead.col1._fontSize > tab.col1._fontSize,
    ("the window sets the lead headline and body larger than the tab (%d/%d against %d/%d)"):format(lead.head._fontSize,
      lead.col1._fontSize, tab.head._fontSize, tab.col1._fontSize))
  check(#Offenders(c, page.paper) == 0 and Cut(page.paper) == nil, "the tab keeps its size and fits as before")
  local long = LayoutClient("Mira Sturmfeder")
  for i, boss in ipairs({ "Schlingwurzler", "Noxxion", "Celebras der Verfluchte", "Erdrutsch", "Prinzessin Theradras", "Faulschnapper" }) do
    Heard(long, { E("boss", "Bodo Kesselring", At(20, 18, 20) + i * 400, { inst = "Maraudon", boss = boss, first = true, lvl = 52 }) })
  end
  long.H:ShowWindow()
  local lp = long.env.RavenquillExpeditionHighlightsFrame.paper.lead
  check(lp.col2:IsShown() and Balanced(lp), ("a long lead story is split evenly over both columns (%.0f and %.0f px)")
    :format(lp.col1:GetStringHeight(), lp.col2:GetStringHeight()))
  local small = LayoutClient("Tamo Eichengrund", "deDE", function(env) Layout.Pin(env.UIParent, 0, 0, 1024, 600) end)
  Heard(small, BUSY_DAY)
  small.H:ShowWindow()
  local sf = small.env.RavenquillExpeditionHighlightsFrame
  local sr = Layout.Rect(sf)
  check(sr.width == 900 and sr.height == 540, ("on a 1024x600 screen the window keeps to 90%% of the height (%dx%d)"):format(sr.width,
    sr.height))
  check(#Offenders(small, sf.paper) == 0 and Cut(sf.paper) == nil, "there too every text sits on the paper, none cut")
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
  for _, b in ipairs({ f.prev, f.next, f.modeButton }) do
    if not (b.label and b.underline and b.label._ink) then return false end
  end
  return true
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
    and cr.left > fr.left + fr.width * 0.9 and cr.bottom > fr.top - 40, "a small inked × sits at the paper's top right")
  local off = Offenders(c, f.paper)
  local lowest = math.huge
  for _, fs in ipairs(Layout.Texts(c, f.paper)) do lowest = math.min(lowest, Layout.Rect(fs).bottom) end
  check(#off == 0 and Cut(f.paper) == nil and lowest >= Layout.Rect(f.prev).top,
    "every text of the issue stays on the paper, above the footer (" .. (off[1] or "none") .. ")")
  check(InkFooter(f) and templates[f.prev] == false and templates[f.modeButton] == false and f.prev:GetText() == "« Vorherige Ausgabe"
    and f.next:GetText() == "Nächste Ausgabe »" and f.modeButton:GetText() == "Chronik"
    and f.issueLabel:GetText() == "Ausgabe vom 20. November", "the footer is printed in ink: no red buttons")
  check(not f.next:IsEnabled() and f.prev:IsEnabled() and Darker(f.prev.label._ink, f.next.label._ink),
    "on the newest issue 'Nächste Ausgabe' is greyed ink, 'Vorherige Ausgabe' full ink")
  local idle = f.prev.label._ink
  f.prev:GetScript("OnEnter")(f.prev)
  check(Darker(f.prev.label._ink, idle) and f.prev.underline:IsShown(), "hovering an ink button darkens and underlines it")
  f.prev:GetScript("OnLeave")(f.prev)
  check(not f.prev.underline:IsShown(), "leaving it takes the underline away")
  Click(f.prev)
  check(f.issueLabel:GetText() == "Ausgabe vom 18. November" and f.next:IsEnabled() and not f.prev:IsEnabled()
    and Darker(f.next.label._ink, f.prev.label._ink), "the ink buttons page back an issue, and the greyed one follows")
  Click(f.next)
  check(f.issueLabel:GetText() == "Ausgabe vom 20. November", "and forward again")
  Click(f.modeButton)
  local panel = f.logPanel
  check(f.mode == "log" and f.msg:IsShown() and not f.paper:IsShown() and f.modeButton:GetText() == "Zeitung"
    and panel._color[4] > 0.9 and panel._color[1] < 0.2 and Layout.Inside(fr, Layout.Rect(panel)),
    "Chronik sets the log on a dark inset panel on the paper, the button reads Zeitung")
  check(Darker(f.footer._ink, { 0.6, 0.6, 0.6 }) and Darker(f.onlyHLText._ink, { 0.6, 0.6, 0.6 }),
    "the log's footer line and checkbox label are printed in ink, readable on the paper")
  Click(f.modeButton)
  check(f.mode == "paper" and f.paper:IsShown(), "Zeitung goes back to the newspaper")
  Click(close)
  check(not f:IsShown(), "the × closes the sheet")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.section("Paper on the /rq Highlights tab")
do
  local c = LayoutClient("Lyra Distelbach")
  Heard(c, BUSY_DAY)
  Heard(c, { E("level", "Bodo Kesselring", At(18, 10), { lvl = 20 }) })
  local page, opt = OpenTab(c, PAGE_W, PAGE_H)
  local paper = page.paper
  check(page.mode == "paper" and paper:IsShown() and not page.msg:IsShown() and page.prev:IsShown() and page.next:IsShown()
    and page.modeButton:GetText() == "Chronik" and page.issueLabel:GetText() == "Ausgabe vom 20. November",
    "the tab shows the newspaper with Vorherige/Nächste Ausgabe and Chronik")
  local off = Offenders(c, paper)
  check(Layout.Inside(Layout.Rect(page), Layout.Rect(paper)) and #off == 0 and Cut(paper) == nil,
    "on the tab every text is on the page, shown in full, no sentence cut (" .. (off[1] or "none") .. ")")
  check(Below(paper, page.prev) and Below(paper, page.next) and Below(paper, page.modeButton)
    and Layout.Inside(Layout.Rect(page), Layout.Rect(page.modeButton)), "the issue buttons sit under the paper, inside the tab")
  check(paper.lead.col2:IsShown() and OpaqueBase(c, paper) ~= nil, "the tab is wide enough for two lead columns, on full paper")
  Click(page.prev)
  local win = c.env.RavenquillExpeditionHighlightsFrame
  check(page.issueLabel:GetText() == "Ausgabe vom 18. November" and not (win and win:IsShown()),
    "Vorherige Ausgabe turns the tab's own paper back a day")
  Click(opt.gear)
  check(c.env.RavenquillExpedition.moduleSettings and opt.panels.Highlights:IsShown() and not page:IsShown(),
    "the settings button above the paper still opens the settings")
  Click(opt.gear)
  check(page:IsShown() and page.mode == "paper" and page.issueLabel:GetText() == "Ausgabe vom 20. November",
    "back from the settings the tab opens today's paper again")
  local narrow = OpenTab(c, 470, PAGE_H)
  off = Offenders(c, narrow.paper)
  check(#off == 0 and not narrow.paper.lead.col2:IsShown(), "a narrow tab sets the lead in one column, all text on the page ("
    .. (off[1] or "none") .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.finish()
