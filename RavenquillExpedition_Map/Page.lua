local ADDON, ns = ...
local M = ns.Map
local L = ns.L
local GS = RavenquillExpedition
local ClassColor, AgeText, ZoneText = M.ClassColor, M.AgeText, M.ZoneText

local Page = { VISIBLE_ROWS = 18, ROW_H = 22, LIST_W = 606 }
function Page.Columns()
  Page.columns = Page.columns or { { "COL_NAME", 8, 170 }, { "COL_LEVEL", 186, 44 }, { "COL_ZONE", 238, 190 }, { "COL_SEEN", 436, 170 } }
  return Page.columns
end

function Page.Cell(parent, font, col)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("LEFT", col[2], 0)
  fs:SetWidth(col[3])
  fs:SetJustifyH("LEFT")
  return fs
end

function Page.CreateRow(content)
  local r = CreateFrame("Button", nil, content)
  r:SetHeight(Page.ROW_H)
  local hover = r:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  hover:SetColorTexture(1, 1, 1, 0.08)
  r.cells = {}
  for c, col in ipairs(Page.Columns()) do r.cells[c] = Page.Cell(r, "GameFontHighlightSmall", col) end
  M.MemberButton(r)
  return r
end

function M:BuildPage(parent)
  local head = CreateFrame("Frame", nil, parent)
  head:SetHeight(20)
  head:SetPoint("TOPLEFT")
  head:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
  for _, col in ipairs(Page.Columns()) do Page.Cell(head, "GameFontNormalSmall", col):SetText(L[col[1]]) end
  parent.list = GS.CreateScrollList(parent, Page.LIST_W, Page.VISIBLE_ROWS * Page.ROW_H,
    { default = { create = Page.CreateRow, update = Page.RenderRow, height = Page.ROW_H } })
  parent.list:SetPoint("TOPLEFT", 0, -24)
  parent.note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  parent.note:SetPoint("BOTTOMLEFT", 8, 6)
  parent:SetScript("OnShow", function()
    GS:RequestRoster()
    GS:Call(M.RenderPage, M)
  end)
  self.page = parent
end

function Page.WhereText(m) return ZoneText(m) or L.ZONE_UNKNOWN end

function Page.SeenText(m)
  local f, text = m.flags or {}, AgeText(M:Age(m))
  local flag = (f.g and L.TT_GHOST) or (f.t and L.TT_TAXI) or (f.s and L.TT_STATIONARY)
  return flag and (text .. " · " .. flag) or text
end

local function Rank(m)
  if m.unshared then return 3 end
  return M:State(m) == "fresh" and 1 or 2
end

function Page.UnsharedMembers(listed)
  local out = {}
  for key, e in GS:EachMember() do
    if e.online and not listed[key] and not GS:IsMe(key) then
      out[#out + 1] = { key = key, name = key, class = e.class, level = e.level, zone = e.zone, unshared = true }
    end
  end
  return out
end

function Page.ListedMembers()
  local list, listed = {}, {}
  for key, m in pairs(M.members) do
    if not m.isSelf and M:State(m) ~= "gone" then
      list[#list + 1] = m
      listed[key] = true
      listed[GS:StripRealm(key) or key] = true
    end
  end
  for _, m in ipairs(Page.UnsharedMembers(listed)) do list[#list + 1] = m end
  table.sort(list, function(a, b)
    local ra, rb = Rank(a), Rank(b)
    if ra ~= rb then return ra < rb end
    return tostring(a.name) < tostring(b.name)
  end)
  return list
end

function Page.RenderRow(r, m)
  r.key, r.unshared = m.key, m.unshared and m or nil
  r.cells[1]:SetText(tostring(m.name) .. (m.fake and (" (" .. L.TEST_MARK .. ")") or ""))
  r.cells[1]:SetTextColor(ClassColor(m.class))
  r.cells[2]:SetText((type(m.level) == "number" and m.level > 0) and tostring(m.level) or "")
  r.cells[3]:SetText(Page.WhereText(m))
  r.cells[4]:SetText(m.unshared and "" or Page.SeenText(m))
  r:SetAlpha(M:State(m) == "stale" and 0.5 or 1)
end

function M:RenderPage()
  local page = self.page
  if not (page and page:IsVisible()) then return end
  local list = Page.ListedMembers()
  page.list:SetData(list)
  page.note:SetText(#list == 0 and L.PAGE_EMPTY or "")
end

function M:RefreshPage() self:RenderPage() end

M:RegisterEvent("GUILD_ROSTER_UPDATE", function() M:RenderPage() end)
