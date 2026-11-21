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

Kit.finish()
