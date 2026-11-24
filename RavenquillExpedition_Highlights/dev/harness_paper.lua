local DEV = (arg[0]:gsub("[^/\\]*$", ""))
local NK = dofile(DEV .. "newskit.lua")
local Kit, Layout, At, E = NK.Kit, NK.Layout, NK.At, NK.E
local check = Kit.check

local ART = { left = 0.02, right = 0.58, top = 0.02, bottom = 0.65 }
local SPEC = { side = 34, mainW = 560, col = 269, gap = 22, sideW = 250, sidePad = 18, icon = 110, colGap = 18, mastW = 232,
  mastH = 58, small = 0.75 }

local function LayoutClient(name, locale, extra)
  return NK.Client(name, locale, function(env, c)
    Layout.Install(c)
    Layout.Pin(env.UIParent, 0, 0, 1920, 1080)
    c.frameMethods.SetDesaturated = function(s, on) s._desaturated = on end
    c.frameMethods.SetVertexColor = function(s, r, g, b) s._tint = { r, g, b } end
    c.frameMethods.SetTextColor = function(s, r, g, b) s._ink = { r, g, b } end
    c.frameMethods.SetJustifyH = function(s, j) s._justify = j end
    if extra then extra(env, c) end
  end)
end

local function Heard(c, entries)
  for _, e in ipairs(entries) do c.H:Add(e, "wire") end
end

local BUSY_DAY = {
  E("boss", "Rika Steinbeck", At(20, 0, 23), { inst = "Dämmerwald", boss = "Emeriss", enc = 3111, first = true }),
  E("boss", "Rika Steinbeck", At(20, 0, 40), { inst = "Dämmerwald", boss = "Lethon", enc = 3112, first = true }),
  E("boss", "Rika Steinbeck", At(20, 1, 16), { inst = "Dämmerwald", boss = "Taerar", enc = 3113, first = true }),
  E("level", "Hanne Moosgrund", At(20, 2, 49), { lvl = 40 }),
  E("level", "Ole Fichtental", At(20, 1, 5), { lvl = 10 }),
  E("skill", "Ole Fichtental", At(20, 3, 11), { skill = "Alchemy", rank = 300 }),
  E("skill", "Ole Fichtental", At(20, 3, 13), { skill = "Leatherworking", rank = 300 }),
  E("rep", "Mira Sturmfeder", At(20, 9), { st = 8, fac = "Die Hydraxianer" }),
  E("mount", "Tamo Eichengrund", At(20, 11), { lvl = 40 }),
  E("rep", "Bodo Kesselring", At(20, 12), { st = 8, fac = "Argentumdämmerung" }),
}

local function Busy(name, locale, extra)
  local c = LayoutClient(name or "Lyra Distelbach", locale, extra)
  Heard(c, BUSY_DAY)
  c.H:ShowWindow()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  return c, f, f.paper
end

local function R(region) return Layout.Rect(region) end
local function Near(a, b) return math.abs(a - b) < 0.5 end
local function Same(a, b) return a and b and Near(a[1], b[1]) and Near(a[2] * 100, b[2] * 100) and Near(a[3] * 100, b[3] * 100) end

local function PaperTextures(c, paper)
  local out = {}
  for _, r in ipairs(c.regions) do
    if r._type == "Texture" and r._parent == paper and r._layer == "BACKGROUND" and r._shown then out[#out + 1] = r end
  end
  return out
end

local function OpaqueBase(c, paper)
  local pr = R(paper)
  for _, t in ipairs(PaperTextures(c, paper)) do
    local r = R(t)
    if t._color and t._color[4] == 1 and (t._alpha or 1) == 1 and r and Layout.Inside(r, pr) then return t, r end
  end
end

local function Grain(c, paper, file)
  for _, t in ipairs(PaperTextures(c, paper)) do if t._file == file then return t end end
end

local function TextsOff(c, paper, rect)
  local off = {}
  for _, fs in ipairs(Layout.Texts(c, paper)) do
    local r = R(fs)
    if not (r and Layout.Inside(rect, r)) then off[#off + 1] = fs._text:sub(1, 40) end
  end
  return off
end

local function CropInsideArt(tc)
  return tc and tc[1] >= ART.left and tc[2] <= ART.right and tc[3] >= ART.top and tc[4] <= ART.bottom and tc[1] < tc[2]
    and tc[3] < tc[4]
end

Kit.section("Paper: an opaque paper-coloured base covers the whole page, under every text, with a light vignette over the grain")
do
  local c, _, paper = Busy()
  local base, rect = OpaqueBase(c, paper)
  check(base ~= nil and Same(base._color, c.H.PAPER), "the page has an opaque base in the paper colour, the size of the whole page")
  local texts = Layout.Texts(c, paper)
  local off = base and TextsOff(c, paper, rect) or { "no base" }
  check(#texts >= 16 and #off == 0, "all " .. #texts .. " text regions sit on that base (" .. (off[1] or "none off") .. ")")
  local grain = Grain(c, paper, c.H.PARCHMENT)
  check(grain and CropInsideArt(grain._tc) and (grain._alpha or 1) < 1 and grain._sublevel > base._sublevel,
    "the parchment art is cropped to its clean middle, translucent, drawn over the base")
  local vignette = Grain(c, paper, c.H.VIGNETTE)
  check(vignette and vignette._sublevel > grain._sublevel and Layout.Inside(R(vignette), R(paper))
    and Layout.Inside(R(paper), R(vignette)), "the vignette lies over the grain and covers the whole page")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.section("Paper: without the parchment file the page is still fully paper-coloured")
do
  local c, _, paper = Busy("Tamo Eichengrund", "deDE", function(env) env.GetFileIDFromPath = function() return nil end end)
  local base, rect = OpaqueBase(c, paper)
  check(base ~= nil and #TextsOff(c, paper, rect) == 0 and not Grain(c, paper, c.H.PARCHMENT),
    "a missing parchment file leaves the plain paper base, no grain")
  check(paper.parchment.source == "color", "the smoke test sees the colour source")
end

local function Offenders(c, paper)
  local pr, out = R(paper), {}
  for _, fs in ipairs(Layout.Texts(c, paper)) do
    local r = R(fs)
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
  return Squash((lead.columns[1]:GetText() or "") .. " " .. (lead.columns[2]:GetText() or ""))
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
  for _, item in ipairs(paper.brief.items) do if item.text:IsShown() then n = n + 1 end end
  return n
end

local function ThirdShown(paper) return paper.third.head:IsShown() and paper.third.body:IsShown() and 1 or 0 end

local function Untold(paper)
  local issue = paper.issue
  local second = issue.second and not paper.second.head:IsShown() and 1 or 0
  return issue.more + #issue.brief - ShownBrief(paper) - ThirdShown(paper) + second
end

local function MoreSays(c, more, n)
  local T = c.ns[NK.HL].NewsLocales.deDE
  if n == 0 then return more == "" or more == T.NO_BRIEF end
  if n == 1 then return more:lower():find("eine weitere meldung", 1, true) ~= nil end
  return more:lower():find(c.ns[NK.HL].News.Count(n, T) .. " weitere meldungen", 1, true) ~= nil
end

local function OpenSized(c, w, h)
  c.H.WINDOW_W, c.H.WINDOW_H = w, h
  c.H:ShowWindow()
  c.H:Refresh()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  return f, f.paper
end

local function MainRight(paper)
  local right = 0
  local lead = paper.lead
  for _, fs in ipairs({ lead.head, lead.dek, lead.columns[1], lead.columns[2], paper.second.body, paper.third.body }) do
    if fs:IsShown() and (fs:GetText() or "") ~= "" then right = math.max(right, R(fs).right) end
  end
  return right
end

local function SidebarRight(paper)
  local main, left = MainRight(paper), math.huge
  for _, item in ipairs(paper.brief.items) do if item.text:IsShown() then left = math.min(left, R(item.text).left) end end
  local rule = R(paper.sideRule)
  return left > main and rule.left > main and rule.right < left and rule.height > rule.width
end

local function LeadBottom(lead)
  return math.min(R(lead.photo.frame).bottom, R(lead.columns[1]).bottom, R(lead.columns[2]).bottom)
end

local function SideBySide(paper)
  local sec, third = paper.second, paper.third
  local s, t, rule = R(sec.head), R(third.head), R(paper.pairRule)
  return Near(t.top, s.top) and R(third.kicker).left > R(sec.body).right and rule.bottom >= R(sec.kicker).top
    and rule.top <= LeadBottom(paper.lead)
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
    "brief items that do not fit are dropped whole and counted in the line about the chronicle (" .. more .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

local STORY_KINDS = {
  { "boss", "boss", { enc = 1100, boss = "Azuregos", inst = "Azshara", first = true } },
  { "clear", "clear", { enc = 672, inst = "Geschmolzener Kern", n = 12, grp = true } },
  { "duel", "duel", { foe = "Bodo Kesselring" } },
  { "epic", "loot", { item = 5001, q = 4 } },
  { "first", "first", { what = "boss", enc = 3111, boss = "Emeriss", inst = "Dämmerwald" } },
  { "group", "group", { inst = "Die Todesminen", with = { "Bodo Kesselring", "Ole Fichtental" }, grp = true } },
  { "level", "level", { lvl = 40 } },
  { "levelmax", "level", { lvl = 60 } },
  { "mount", "mount", { epic = true } },
  { "pvp", "pvp", { pk = "rank", pr = 3, name = "Feldwebel" } },
  { "ready", "ready", { raid = "mc" } },
  { "rep", "rep", { st = 8, fac = "Argentumdämmerung" } },
  { "run", "run", { inst = "Maraudon", boss = "Noxxion", n = 8, nf = 8, first = true } },
  { "skill", "skill", { skill = "Alchemy", rank = 300 } },
  { "visit", "visit", { inst = "Uldaman", n = 3 } },
}
local STORY_SPEC = { lead = { "first", { what = "level", lvl = 60 } } }
for _, row in ipairs(STORY_KINDS) do STORY_SPEC[row[1]] = { row[2], row[3] } end
local STORY_PEOPLE = { "Hanne Moosgrund", "Tamo Eichengrund", "Mira Sturmfeder", "Rika Steinbeck" }
local SHORT_SHEETS = { { 640, 395 }, { 640, 470 }, { 900, 480 } }

local function StoryDay(lineUp)
  local c = LayoutClient("Lyra Distelbach")
  for i, kind in ipairs(lineUp) do
    local spec = STORY_SPEC[kind]
    c.H:Add(E(spec[1], STORY_PEOPLE[i], At(20, 9 + i), spec[2]), "wire")
  end
  return c
end

local function Bare(story) return story.head:IsShown() and (story.body:GetText() or "") == "" end

local function ReviewSheet(c, paper, tag, out)
  local off = Offenders(c, paper)
  if off[1] then out.off[#out.off + 1] = tag .. ": " .. off[1] end
  for _, story in ipairs({ paper.second, paper.third }) do
    if Bare(story) then out.bare[#out.bare + 1] = tag .. ": " .. story.head:GetText() end
  end
  local more, n = paper.brief.more:GetText() or "", Untold(paper)
  if not MoreSays(c, more, n) then out.uncounted[#out.uncounted + 1] = ("%s: %d left out, the line says '%s'"):format(tag, n, more) end
end

local function ReviewLineUp(kind, slot, lineUp, out)
  local c = StoryDay(lineUp)
  for _, size in ipairs(SHORT_SHEETS) do
    local f, paper = OpenSized(c, size[1], size[2])
    local story = slot == 2 and paper.issue.second or paper.issue.extra[1]
    if story and story.kind == kind then
      out.seen[kind .. slot] = true
      ReviewSheet(c, paper, ("%s as story %d at %dx%d"):format(kind, slot, size[1], size[2]), out)
    end
    f:Hide()
  end
  if c.errors[1] then out.errors[#out.errors + 1] = tostring(c.errors[1]) end
end

Kit.section("Paper: on a short page every kind of story beside or under the lead keeps its headline with at least one sentence, "
  .. "or leaves the page whole and is counted in the line about the chronicle")
do
  local out = { off = {}, bare = {}, uncounted = {}, seen = {}, errors = {} }
  for _, row in ipairs(STORY_KINDS) do
    local kind = row[1]
    ReviewLineUp(kind, 2, { "lead", kind, "duel" }, out)
    ReviewLineUp(kind, 3, { "lead", kind == "clear" and "levelmax" or "clear", kind, "duel" }, out)
  end
  local missing = {}
  for _, row in ipairs(STORY_KINDS) do
    if not (out.seen[row[1] .. 2] or out.seen[row[1] .. 3]) then missing[#missing + 1] = row[1] end
  end
  check(#missing == 0 and out.seen.ready2 and out.seen.ready3, "every kind of story lands second or third, a raid ready story "
    .. "both (" .. (missing[1] or "all seen") .. ")")
  check(#out.off == 0, "every text stays on the page (" .. #out.off .. " sheets: " .. (out.off[1] or "none") .. ")")
  check(#out.bare == 0, "no story keeps a headline without a sentence under it (" .. #out.bare .. " sheets: "
    .. (out.bare[1] or "none") .. ")")
  check(#out.uncounted == 0, "a story left out is counted in the line about the chronicle (" .. (out.uncounted[1] or "none") .. ")")
  check(#out.errors == 0, "no Lua errors (" .. tostring(out.errors[1]) .. ")")
end

local function Click(b) b:GetScript("OnClick")(b) end

local function Bottom(c, paper)
  local low = math.huge
  for _, fs in ipairs(Layout.Texts(c, paper)) do low = math.min(low, R(fs).bottom) end
  return low
end

local function MetaRow(paper)
  local meta = paper.meta
  local l, m, r, page = R(meta.left), R(meta.mid), R(meta.right), R(paper)
  local gapL, gapR = m.left - l.right, r.left - m.right
  return Near(l.top, m.top) and Near(m.top, r.top) and Near(l.left - page.left, SPEC.side)
    and Near(page.right - r.right, SPEC.side) and gapL > 12 and Near(gapL, gapR)
end

local function MetaRules(paper, ink, rule)
  local meta, mast = paper.meta, R(paper.masthead.texture)
  local top, bottom, text = R(meta.top), R(meta.bottom), R(meta.left)
  return top.height == 2 and Same(meta.top._color, ink) and bottom.height == 1 and Same(meta.bottom._color, rule)
    and top.top <= mast.bottom and top.bottom >= text.top and bottom.top <= text.bottom and Near(top.width, 900 - 2 * SPEC.side)
    and Near(bottom.width, top.width)
end

local function UsesArt(c, pattern)
  for _, r in ipairs(c.regions) do
    if r._type == "Texture" and type(r._file) == "string" and r._file:find(pattern) then return r._file end
  end
end

Kit.section("Masthead: Rabenblatt centred, then one meta line between a 2 px ink rule and a 1 px rule")
do
  local c, _, paper = Busy()
  local H = c.H
  local mast = R(paper.masthead.texture)
  check(paper.masthead.texture._file == H.MASTHEAD and not paper.masthead.text:IsShown() and mast.width == SPEC.mastW
    and mast.height == SPEC.mastH and Near((mast.left + mast.right) / 2, R(paper).left + 450),
    ("the masthead is the texture, %dx%d px, centred on the sheet"):format(mast.width, mast.height))
  local meta = paper.meta
  check(meta.left:GetText() == "Gildenblatt der Ravenquill Expedition" and meta.mid:GetText() == "Freitag, 20. November"
    and meta.right:GetText() == "Nr. 1 · 1 Kupfer", "the meta line: paper's name, weekday and date, number and price")
  check(MetaRow(paper), "its three parts share one row: name flush left, number and price flush right, the date spaced between")
  check(MetaRules(paper, H.INK, H.RULE), "a 2 px ink rule runs above the line, a 1 px rule under it, across the content width")
  check(meta.left._fontSize == 13 and Same(meta.left._ink, H.INK_SOFT) and Same(meta.right._ink, H.INK_SOFT),
    "the meta line is set at 13 px in the soft ink")
  check(paper.ears == nil and paper.mastRules == nil and paper.lead.cap == nil and paper.brief.dots == nil
    and H.DROP_CAPS == nil and H.DOTTED == nil and H.IN_BRIEF_ART == nil, "no ears, no double rules, no drop cap, no dotted rules")
  local art = UsesArt(c, "dropcaps") or UsesArt(c, "dotted") or UsesArt(c, "inbrief")
  check(art == nil, "no region draws the old drop cap, dotted rule or heading art (" .. tostring(art) .. ")")
  local en = Busy("Mira Sturmfeder", "enUS")
  local ep = en.env.RavenquillExpeditionHighlightsFrame.paper
  check(ep.meta.left:GetText() == "Guild paper of the Ravenquill Expedition" and ep.meta.mid:GetText() == "Friday, November 20"
    and ep.meta.right:GetText() == "No. 1 · 1 copper" and MetaRow(ep), "the English meta line")
  check(ep.brief.title:GetText() == "In brief" and paper.brief.title:GetText() == "In Kürze", "each language's In Kürze heading")
  check(#c.errors == 0 and #en.errors == 0, "no Lua errors (" .. tostring(c.errors[1] or en.errors[1]) .. ")")
end

local function Woodcut(H, photo, size)
  local frame, icon = R(photo.frame), R(photo.icon)
  local tint = photo.icon._tint
  local ink = photo.frame._color
  return Near(frame.width, size) and Near(frame.height, size) and icon.left - frame.left == 3 and frame.right - icon.right == 3
    and frame.top - icon.top == 3 and icon.bottom - frame.bottom == 3 and photo.icon._desaturated == true
    and tint[1] > tint[2] and tint[2] > tint[3] and Same(ink, H.INK) and ink[4] == 1
end

local function Columns(lead, scale)
  local frame, a, b = R(lead.photo.frame), R(lead.columns[1]), R(lead.columns[2])
  local gap, head = SPEC.colGap * scale, R(lead.head)
  return Near(a.left, frame.right + gap) and Near(b.left, a.right + gap) and Near(a.top, frame.top) and Near(b.top, a.top)
    and Near(a.width, b.width) and Near(b.right, head.right)
end

local function Leading(fs, size, lineHeight)
  return Near(fs._fontSize * 10, size * 10) and Near((fs._spacing or 0) * 10, (lineHeight - 1) * size * 10)
end

local function TimeAbove(paper, H)
  local items, n = paper.brief.items, 0
  for i, item in ipairs(items) do
    if item.text:IsShown() then
      local t, x, rule, nextItem = R(item.time), R(item.text), R(item.rule), items[i + 1]
      if not (t.bottom >= x.top - 0.5 and Near(t.left, x.left) and Same(item.time._ink, H.ACCENT) and rule.top <= x.bottom
        and rule.height == 1 and item.rule:IsShown()) then return false end
      if nextItem and nextItem.text:IsShown() and R(nextItem.time).top > rule.bottom then return false end
      n = n + 1
    end
  end
  return n > 0
end

local function Morpheus(H, list)
  for _, fs in ipairs(list) do if fs._fontFile ~= H.TITLE_FONT then return false end end
  return true
end

local function Body(H, list)
  for _, fs in ipairs(list) do if fs._fontFile == H.TITLE_FONT or not fs._fontFile then return false end end
  return true
end

Kit.section("Grid: the lead spans two columns, two stories under it, In Kürze as the right-hand column")
do
  local c, _, paper = Busy()
  local H, lead = c.H, paper.lead
  check(lead.kicker:GetText() == H.Upper(paper.issue.lead.kicker) and lead.kicker:GetText():find("^%u")
    and lead.kicker._fontSize == 12 and Same(lead.kicker._ink, H.ACCENT), "the lead's kicker: 12 px capitals in the accent colour")
  local head, page = R(lead.head), R(paper)
  check(Near(head.left - page.left, SPEC.side) and Near(head.width, SPEC.mainW) and head.right < R(paper.sideRule).left,
    ("the lead spans the first two columns (%.0f px wide)"):format(head.width))
  check(lead.head._fontSize == 34 and Leading(lead.dek, 16, 1.35) and Same(lead.dek._ink, H.INK_SOFT),
    "a 34 px headline and a 16 px dek in the soft ink")
  local dek, rule = R(lead.dek), R(lead.dekRule)
  check(rule.height == 1 and Same(lead.dekRule._color, H.RULE) and rule.top <= dek.bottom and Near(rule.width, SPEC.mainW)
    and R(lead.photo.frame).top <= rule.bottom, "a 1 px rule under the dek, the picture row below it")
  check(Woodcut(H, lead.photo, SPEC.icon), "the picture is the icon at 110 px in a 3 px ink frame, desaturated and tinted warm")
  local cap, frame = R(lead.photo.caption), R(lead.photo.frame)
  check(lead.photo.caption:GetText() == paper.issue.lead.caption and cap.top <= frame.bottom and lead.photo.caption._fontSize == 12
    and Near((cap.left + cap.right) / 2, (frame.left + frame.right) / 2), "its 12 px caption is centred under it")
  check(Columns(lead, 1), "the lead body runs in two equal text columns beside the picture, 18 px apart")
  check(Leading(lead.columns[1], 15, 1.45) and Leading(lead.columns[2], 15, 1.45), "the lead body is 15 px with a 1.45 line height")
  check(LeadText(lead) == Squash(table.concat(paper.issue.lead.body, " ")) and (lead.columns[2]:GetText() or "") ~= "",
    "the whole lead body flows from the first column into the second")
  check(SideBySide(paper) and paper.third.head:GetText() == paper.issue.extra[1].head
    and paper.third.kicker:GetText() == H.Upper(paper.issue.extra[1].kicker), "two stories side by side under the lead")
  local pr, sec, third = R(paper.pairRule), R(paper.second.head), R(paper.third.head)
  check(pr.height == 2 and Same(paper.pairRule._color, H.INK) and Near(sec.width, SPEC.col) and Near(third.left - sec.right, SPEC.gap)
    and paper.second.head._fontSize == 20 and Leading(paper.second.body, 14.5, 1.42),
    "behind a 2 px ink rule, two 269 px columns 22 px apart: 20 px headlines, 14.5 px bodies")
  check(SidebarRight(paper), "In Kürze is the right-hand column, behind a vertical rule")
  local side, title = R(paper.sideRule), R(paper.brief.title)
  check(side.width == 2 and Same(paper.sideRule._color, H.INK) and Near(side.left - page.left, SPEC.side + SPEC.mainW + SPEC.gap)
    and Near(title.left, side.right + SPEC.sidePad) and Near(R(paper).right - title.right, SPEC.side),
    "a 2 px ink rule on its left, 250 px for the column, 18 px padding")
  check(paper.brief.title._fontSize == 22 and paper.brief.title._justify ~= "LEFT" and Near(title.top, side.top),
    "its 22 px heading is centred at the top of the column")
  check(TimeAbove(paper, H) and ShownBrief(paper) == #paper.issue.brief - 1,
    "each item: its time in the accent on its own line, the text under it, a 1 px rule before the next")
  local item = paper.brief.items[1]
  check(item.time._fontSize == 12 and item.time:GetText() == "01:05 Uhr" and Leading(item.text, 14, 1.4),
    "times are 12 px, item texts 14 px")
  check(Morpheus(H, { lead.head, paper.second.head, paper.third.head, paper.brief.title, paper.masthead.text }),
    "headlines and the In Kürze heading ask for Morpheus")
  check(Body(H, { lead.columns[1], lead.dek, lead.kicker, paper.second.body, item.text, item.time, paper.meta.left }),
    "body, dek, kickers, brief and meta use the UI font")
  local twice = nil
  for _, it in ipairs(paper.brief.items) do
    if it.text:IsShown() and it.text:GetText():find(paper.third.head:GetText(), 1, true) then twice = it.text:GetText() end
  end
  check(twice == nil, "no story is told twice (" .. tostring(twice) .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.section("Fonts: without Morpheus the headlines fall back to the UI font at their size")
do
  local c, _, paper = Busy("Lyra Distelbach", "deDE", function(_, cl)
    local set = cl.frameMethods.SetFont
    cl.frameMethods.SetFont = function(s, file, size)
      if file == "Fonts\\MORPHEUS.TTF" then return false end
      return set(s, file, size)
    end
  end)
  local head = paper.lead.head
  check(head._fontSize == 34 and head._fontFile ~= nil and head._fontFile ~= c.H.TITLE_FONT,
    "the lead headline keeps 34 px in the UI font (" .. tostring(head._fontFile) .. ")")
  check(paper.brief.title._fontSize == 22 and paper.second.head._fontSize == 20 and #Offenders(c, paper) == 0,
    "the other headlines too, every text still on the paper")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.section("Lead columns: a long lead story balances over both columns, whole sentences only")
do
  local long = LayoutClient("Mira Sturmfeder")
  for i, boss in ipairs({ "Emeriss", "Lethon", "Taerar", "Ysondre" }) do
    Heard(long, { E("boss", "Bodo Kesselring", At(20, 18, 20) + i * 400, { inst = "Dämmerwald", boss = boss, enc = 3110 + i, first = true, lvl = 60 }) })
  end
  local _, lpaper = OpenSized(long, 640, 640)
  local cols = lpaper.lead.columns
  local a, b = R(cols[1]), R(cols[2])
  check((cols[1]:GetText() or "") ~= "" and (cols[2]:GetText() or "") ~= "" and a.height >= b.height,
    ("the first column is filled first, the second takes the rest (%.0f / %.0f px)"):format(a.height, b.height))
  check(a.height - b.height <= cols[1]._fontSize * Layout.LINE_EM + cols[1]._spacing + 0.5,
    "the two columns end within one line of each other")
  check(Columns(lpaper.lead, SPEC.small) and #Offenders(long, lpaper) == 0 and Cut(lpaper) == nil,
    "both stand beside the picture, nothing leaves the page or is cut")
  check(#long.errors == 0, "no Lua errors (" .. tostring(long.errors[1]) .. ")")
end

Kit.section("Window: 900 wide, at most 780 high and 90% of the screen, sized to the issue, smaller type on a small screen")
do
  local c, f = Busy()
  local r = R(f)
  local gap = Bottom(c, f.paper) - R(f.footerRule).top
  check(r.width == 900 and r.height <= 780 and r.height >= c.H.WINDOW_MIN_H and gap >= 0 and gap < 60,
    ("on a 1920x1080 screen the sheet is 900 wide and ends just under its last text (%.0fx%.0f, %.0f px spare)"):format(r.width,
      r.height, gap))
  local off, cut = Offenders(c, f.paper), Cut(f.paper)
  check(#off == 0 and cut == nil, "at 900x780 every text on the paper, none cut (" .. (off[1] or tostring(cut)) .. ")")
  check(ThirdShown(f.paper) == 1 and ShownBrief(f.paper) + 1 == #f.paper.issue.brief,
    "a busy day fills the page: a third story beside the second, every other report in the brief")
  local quiet = LayoutClient("Mira Sturmfeder")
  Heard(quiet, { E("level", "Bodo Kesselring", At(20, 10), { lvl = 20 }), E("mount", "Tamo Eichengrund", At(20, 11), { lvl = 40 }) })
  quiet.H:ShowWindow()
  local qf = quiet.env.RavenquillExpeditionHighlightsFrame
  local qr = R(qf)
  check(qr.width == 900 and qr.height < r.height and qr.height >= quiet.H.WINDOW_MIN_H and #Offenders(quiet, qf.paper) == 0
    and Cut(qf.paper) == nil, ("a quiet day gives a shorter sheet, nothing cut (%.0fx%.0f against %.0f)"):format(qr.width, qr.height,
      r.height))
  check(not qf.paper.third.head:IsShown() and Near(R(qf.paper.second.body).width, SPEC.mainW),
    "without a third story the second one takes both columns")
  local small, sf = Busy("Tamo Eichengrund", "deDE", function(env) Layout.Pin(env.UIParent, 0, 0, 1024, 600) end)
  local sr = R(sf)
  check(sr.width == 900 and sr.height <= 540, ("on a 1024x600 screen the window keeps to 90%% of the height (%dx%d)"):format(sr.width,
    sr.height))
  local soff, scut = Offenders(small, sf.paper), Cut(sf.paper)
  check(#soff == 0 and scut == nil, "at 1024x600 too every text on the paper, none cut (" .. (soff[1] or tostring(scut)) .. ")")
  local low, s = sf.paper.lead, SPEC.small
  check(sf.paper.scale == s and low.head._fontSize == 34 * s and low.columns[1]._fontSize == 15 * s
    and sf.paper.brief.items[1].text._fontSize == 14 * s and Woodcut(small.H, low.photo, SPEC.icon * s),
    ("there every size shrinks by one factor: headline and body %.1f/%.2f px, a %.1f px picture"):format(low.head._fontSize,
      low.columns[1]._fontSize, R(low.photo.frame).width))
  check(Columns(low, s) and SidebarRight(sf.paper) and SideBySide(sf.paper) and TimeAbove(sf.paper, small.H)
    and Near(R(sf.paper).right - R(sf.paper.sideRule).left, SPEC.side + SPEC.sideW * s) and MetaRow(sf.paper),
    "and the same grid inside the same 34 px margins: the fixed parts scaled, the story columns share the rest")
  check(#c.errors == 0 and #small.errors == 0, "no Lua errors (" .. tostring(c.errors[1] or small.errors[1]) .. ")")
end

local function InkClient()
  local templates = {}
  local c = LayoutClient("Lyra Distelbach", "deDE", function(env)
    local create = env.CreateFrame
    env.CreateFrame = function(otype, name, parent, template)
      local f = create(otype, name, parent, template)
      templates[f] = template or false
      return f
    end
  end)
  return c, templates
end

local function ShadowSides(c, f)
  local fr, sides = R(f), {}
  for _, r in ipairs(c.regions) do
    local col, rect = r._color, r._type == "Texture" and r._parent == f and R(r)
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
    if not (b.label and b.underline and b.label._ink and b.label._fontSize == 13) then return false end
  end
  return f.issueLabel._fontSize == 13
end

local function Spread(f)
  local items = { R(f.prev.label), R(f.issueLabel), R(f.next.label), R(f.chronicle.label) }
  local fr = R(f)
  local g1, g2, g3 = items[2].left - items[1].right, items[3].left - items[2].right, items[4].left - items[3].right
  return g1 > 24 and math.abs(g1 - g2) < 9 and math.abs(g2 - g3) < 9 and items[1].left - fr.left < SPEC.side + 4
    and fr.right - items[4].right < SPEC.side + 4 and Near(items[1].top, items[4].top) and Near(items[2].top, items[3].top)
end

local function Live(b) return b:IsEnabled() and not b.underline:IsShown() end

Kit.section("Window: a frameless sheet of paper with a soft shadow, an inked close mark and an inked footer")
do
  local c, templates = InkClient()
  Heard(c, BUSY_DAY)
  Heard(c, { E("level", "Bodo Kesselring", At(18, 10), { lvl = 20 }) })
  c.H:ShowWindow()
  local f = c.env.RavenquillExpeditionHighlightsFrame
  local fr, pr = R(f), R(f.paper)
  check(templates[f] == false and not rawget(f, "NineSlice") and not rawget(f, "CloseButton") and not rawget(f, "portrait"),
    "the window is a plain frame: no template, no portrait, no title bar")
  check(OpaqueBase(c, f) ~= nil and pr.left == fr.left and pr.right == fr.right and pr.top == fr.top and pr.bottom == fr.bottom,
    "the whole window is paper: its own paper base and the newspaper cover it edge to edge")
  check(ShadowSides(c, f), "translucent black shadow strips lie outside the sheet on all four sides")
  local inUI = false
  for _, name in ipairs(c.env.UISpecialFrames) do inUI = inUI or name == "RavenquillExpeditionHighlightsFrame" end
  check(inUI and rawget(f, "_scripts").OnDragStart ~= nil, "Esc closes the sheet and it can be dragged")
  local close = f.close
  local cr = R(close)
  check(close:GetText() == "×" and templates[close] == false and cr.right <= fr.right and cr.top <= fr.top
    and cr.left > fr.left + fr.width * 0.9 and cr.bottom > fr.top - 40 and not close.underline:IsShown()
    and close.label._fontSize == 22, "a 22 px inked × sits at the paper's top right, not underlined")
  check(cr.bottom > R(f.paper.meta.top).top, "the × keeps clear of the meta line")
  local off = Offenders(c, f.paper)
  local lowest = Bottom(c, f.paper)
  local rule = R(f.footerRule)
  check(#off == 0 and Cut(f.paper) == nil and lowest >= rule.top,
    "every text of the issue stays on the paper, above the footer (" .. (off[1] or "none") .. ")")
  check(rule.height == 2 and Same(f.footerRule._color, c.H.INK) and rule.bottom >= R(f.prev).top - 8 and f.footerRules == nil,
    "one 2 px ink rule runs between the issue and the footer")
  check(InkFooter(f) and templates[f.prev] == false and templates[f.chronicle] == false and f.prev:GetText() == "« Vorherige Ausgabe"
    and f.next:GetText() == "Nächste Ausgabe »" and f.chronicle:GetText() == "Chronik"
    and f.issueLabel:GetText() == "Ausgabe vom 20. November", "the footer links are 13 px ink text: no red buttons")
  check(Same(f.issueLabel._ink, c.H.INK) and Spread(f), "previous, issue date, next and Chronik spread evenly across the footer")
  check(not f.next:IsEnabled() and not f.next.underline:IsShown() and Live(f.prev) and Live(f.chronicle)
    and Darker(f.prev.label._ink, f.next.label._ink), "on the newest issue 'Nächste Ausgabe' is greyed, the live links in ink")
  check(R(f.prev).width >= utf8.len("« Vorherige Ausgabe") * 13 * Layout.CHAR_EM - 0.5, "each link is as wide as its words")
  local idle = f.prev.label._ink
  f.prev:GetScript("OnEnter")(f.prev)
  check(Darker(f.prev.label._ink, idle) and f.prev.underline:IsShown(), "hovering a link darkens and underlines it")
  f.prev:GetScript("OnLeave")(f.prev)
  check(not f.prev.underline:IsShown() and not Darker(f.prev.label._ink, idle), "leaving it gives back the plain ink")
  Click(f.prev)
  check(f.issueLabel:GetText() == "Ausgabe vom 18. November" and Live(f.next) and not f.prev:IsEnabled()
    and Darker(f.next.label._ink, f.prev.label._ink) and Spread(f), "the links page back an issue, and the greyed one follows")
  Click(f.next)
  check(f.issueLabel:GetText() == "Ausgabe vom 20. November", "and forward again")
  check(f.msg == nil and f.logPanel == nil, "the sheet holds the newspaper only: no log and no dark log panel")
  Click(f.chronicle)
  local page = c.env.RavenquillExpeditionOverview.optView.pages.Highlights
  check(not f:IsShown() and c.env.RavenquillExpedition.optionsModule == "Highlights" and page:IsShown() and page.msg ~= nil,
    "Chronik closes the sheet and opens the Chronik in the /rq Highlights tab")
  c.H:ShowWindow()
  Click(close)
  check(not f:IsShown(), "the × closes the sheet")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

local function InkEdges(c, owner)
  local n = 0
  for _, r in ipairs(c.regions) do
    if r._type == "Texture" and r._parent == owner and r._shown and Same(r._color, c.H.INK) then n = n + 1 end
  end
  return n
end

local function Overlap(a, b) return a.left < b.right and b.left < a.right and a.bottom < b.top and b.bottom < a.top end

local function Covered(c, paper, button)
  local br = R(button)
  for _, fs in ipairs(Layout.Texts(c, paper)) do
    if fs ~= button.label and Overlap(R(fs), br) then return fs._text:sub(1, 40) end
  end
  return "none"
end

local function UnderWords(lead, br)
  for _, col in ipairs(lead.columns) do
    local r = R(col)
    if (col:GetText() or "") ~= "" and br.left < r.right and r.left < br.right and br.top > r.bottom then return false end
  end
  return br.left >= R(lead.columns[1]).left - 0.5
end

Kit.section("Empty paper: 'Testeinträge hinzufügen' is an inked box under the lead's last words")
do
  local c, templates = InkClient()
  for _, size in ipairs({ { 900, 780 }, { 640, 470 } }) do
    local f, paper = OpenSized(c, size[1], size[2])
    local b = paper.lead.tests
    local br, lead = R(b), paper.lead
    local tag = (" at %dx%d"):format(size[1], size[2])
    check(templates[b] == false and b:IsShown() and b.label._text == "Testeinträge hinzufügen" and Same(b.label._ink, c.H.INK)
      and b.label._fontSize >= 15 * SPEC.small and InkEdges(c, b) == 8,
      "a plain button, no red template: ink words framed by a double ink rule" .. tag)
    check(UnderWords(lead, br) and br.right <= R(paper.sideRule).left and br.bottom >= R(paper.pairRule).top, "it sits under the lead's last words, inside the main column, above the next story" .. tag)
    local covered = Covered(c, paper, b)
    check(Layout.Inside(br, R(b.label)) and not Layout.Truncated(b.label) and covered == "none",
      "its words fit inside the box and no other text runs into it (" .. covered .. ")" .. tag)
    f:Hide()
  end
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.section("Paper: the picture's caption is never cut")
do
  local c, _, paper = Busy()
  local function CaptionWith(text)
    paper.lead.photo.text = text
    paper:GetScript("OnSizeChanged")()
    local cap = paper.lead.photo.caption
    return cap:IsShown() and cap:GetText() or "", cap
  end
  local text, cap = CaptionWith("Scharlachrotes Kloster")
  check(text == "Scharlachrotes Kloster" and not Layout.Truncated(cap) and R(cap).width == SPEC.icon,
    "a long word that fits the picture's width stays whole in the caption (" .. text .. ")")
  local longText, long = CaptionWith("Schattenfangfestungsruinenkeller")
  check(longText == "" and not Layout.Truncated(long), "a word wider than the picture leaves the caption out (" .. longText .. ")")
  local many = CaptionWith("Ein Bild aus dem Kloster der Scharlachroten mit drei Bossen und einem Hund")
  check(many == "", "so does a caption longer than about three lines (" .. many .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.finish()
