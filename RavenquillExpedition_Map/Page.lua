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
    { default = { create = Page.CreateRow, update = Page.RenderRow, height = Page.ROW_H },
      group = { create = Page.CreateGroupRow, update = Page.RenderGroupRow, height = Page.ROW_H } })
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

local ON_MAP = { title = "GROUP_ON_MAP", alpha = 1 }
local NO_POSITION = { title = "GROUP_NO_POSITION", alpha = 0.5 }

local STATES = {
  onMap = { rank = 1, group = ON_MAP, last = Page.SeenText },
  stale = { rank = 2, group = NO_POSITION, last = function(m) return L.REASON_STALE:format(math.floor(M:Age(m) / 60)) end },
  notSharing = { rank = 3, group = NO_POSITION, last = function() return L.TT_NOT_SHARING end },
  noAddon = { rank = 4, group = NO_POSITION, last = function() return L.REASON_NO_ADDON end },
}

function M:PositionState(m)
  if not m.unshared then return self:State(m) == "fresh" and "onMap" or "stale" end
  if m.heard then return "stale" end
  return GS:IsPeer(m.key) and "notSharing" or "noAddon"
end

function M:StateText(m) return STATES[self:PositionState(m)].last(m) end

function Page.UnsharedMembers(listed)
  local out = {}
  for key, e in GS:EachMember() do
    if e.online and not listed[key] and not GS:IsMe(key) then
      out[#out + 1] = { key = key, name = key, class = e.class, level = e.level, zone = e.zone, unshared = true,
        heard = M.lastHeard[key] }
    end
  end
  return out
end

function Page.ListedMembers()
  local list, listed = {}, {}
  for key, m in pairs(M.members) do
    if not m.isSelf then
      list[#list + 1] = m
      listed[key] = true
      listed[GS:StripRealm(key) or key] = true
    end
  end
  for _, m in ipairs(Page.UnsharedMembers(listed)) do list[#list + 1] = m end
  local stateOf = {}
  for _, m in ipairs(list) do stateOf[m] = STATES[M:PositionState(m)] end
  table.sort(list, function(a, b)
    if stateOf[a].rank ~= stateOf[b].rank then return stateOf[a].rank < stateOf[b].rank end
    return tostring(a.name) < tostring(b.name)
  end)
  return list, stateOf
end

function Page.Rows()
  local list, stateOf = Page.ListedMembers()
  local count, rows, open = {}, {}, nil
  for _, m in ipairs(list) do count[stateOf[m].group] = (count[stateOf[m].group] or 0) + 1 end
  for _, m in ipairs(list) do
    local group = stateOf[m].group
    if group ~= open then
      open = group
      rows[#rows + 1] = { rowKind = "group", text = L[group.title]:format(count[group]) }
    end
    rows[#rows + 1] = m
  end
  return rows, #list
end

function Page.RenderRow(r, m)
  local state = STATES[M:PositionState(m)]
  r.key, r.unshared = m.key, m.unshared and m or nil
  r.cells[1]:SetText(tostring(m.name) .. (m.fake and (" (" .. L.TEST_MARK .. ")") or ""))
  r.cells[1]:SetTextColor(ClassColor(m.class))
  r.cells[2]:SetText((type(m.level) == "number" and m.level > 0) and tostring(m.level) or "")
  r.cells[3]:SetText(Page.WhereText(m))
  r.cells[4]:SetText(state.last(m))
  r:SetAlpha(state.group.alpha)
end

function Page.CreateGroupRow(content)
  local r = CreateFrame("Frame", nil, content)
  r:SetHeight(Page.ROW_H)
  r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  r.label:SetPoint("LEFT", 2, 0)
  return r
end

function Page.RenderGroupRow(r, group) r.label:SetText(group.text) end

function M:RenderPage()
  local page = self.page
  if not (page and page:IsVisible()) then return end
  local rows, members = Page.Rows()
  page.list:SetData(rows)
  page.note:SetText(members == 0 and L.PAGE_EMPTY or "")
end

function M:RefreshPage() self:RenderPage() end

M:RegisterEvent("GUILD_ROSTER_UPDATE", function() M:RenderPage() end)
