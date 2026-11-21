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

local function WholeUnits(text, paragraphs)
  if text == "" then return true end
  for n = 1, #paragraphs do if text == table.concat(paragraphs, "\n", 1, n) then return true end end
  local first = paragraphs[1] or ""
  return first:sub(1, #text) == text and text:find("[%.!?]$") ~= nil and first:sub(#text + 1, #text + 1) == " "
end

local function StoryTexts(paper)
  local issue, lead, sec = paper.issue, paper.lead, paper.second
  local leadBody = issue.lead.body
  return {
    { lead.col1:GetText(), lead.col2:IsShown() and { leadBody[1] } or leadBody },
    { lead.col2:IsShown() and lead.col2:GetText() or "", { leadBody[2] } },
    { sec.body:GetText(), issue.second.body },
  }
end

local function Cut(paper)
  for _, pair in ipairs(StoryTexts(paper)) do
    if not WholeUnits(pair[1] or "", pair[2]) then return pair[1] end
  end
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
  check(paper.lead.col2:IsShown() and paper.lead.col1:GetText() == paper.issue.lead.body[1], "the lead body runs in two columns")
  check(ShownBrief(paper) == #paper.issue.brief, "every brief line fits in the window")
  f:Hide()
  f, paper = OpenSized(c, 640, 470)
  off = Offenders(c, paper)
  check(#off == 0, "in a short window every text still stays on the page (" .. (off[1] or "none") .. ")")
  local cut = Cut(paper)
  check(cut == nil, "bodies keep whole paragraphs or whole sentences, never a cut one (" .. tostring(cut) .. ")")
  local dropped = #paper.issue.brief - ShownBrief(paper)
  local more = paper.brief.more:GetText() or ""
  check(dropped > 0 and more:find(c.ns[NK.HL].News.Count(paper.issue.more + dropped, c.ns[NK.HL].NewsLocales.deDE), 1, true),
    "brief lines that do not fit are dropped whole and counted in the line about the chronicle (" .. more .. ")")
  f:Hide()
  f, paper = OpenSized(c, 640, 430)
  off, cut = Offenders(c, paper), Cut(paper)
  local shortened = paper.lead.col1:GetText() ~= paper.issue.lead.body[1]
    or paper.second.body:GetText() ~= table.concat(paper.issue.second.body, "\n")
  check(#off == 0 and cut == nil and shortened, "a very short page drops whole paragraphs, then whole sentences, and keeps "
    .. "everything on the page (" .. (off[1] or tostring(cut)) .. ")")
  f:Hide()
  _, paper = OpenSized(c, 500, 640)
  off = Offenders(c, paper)
  check(#off == 0 and not paper.lead.col2:IsShown() and paper.lead.col1:GetText():find(paper.issue.lead.body[1], 1, true),
    "a narrow page sets the lead body in one column, everything on the page (" .. (off[1] or "none") .. ")")
  check(#c.errors == 0, "no Lua errors (" .. tostring(c.errors[1]) .. ")")
end

Kit.finish()
