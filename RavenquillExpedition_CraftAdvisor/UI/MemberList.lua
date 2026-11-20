local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local G, MEMBER_ROW_H, C = P.G, P.MEMBER_ROW_H, P.C
local SUB_TINT, SingleLine = P.SUB_TINT, P.SingleLine
local SetTip, ClassColor, ClassName, Hex = P.SetTip, P.ClassColor, P.ClassName, P.Hex
local GainText, ShortSlotName, SpecHowText, Ago = P.GainText, P.ShortSlotName, P.SpecHowText, P.Ago
local SourceText, ProfName, GainFont = P.SourceText, P.ProfName, P.GainFont

UI.collapsed = { online = false, offline = true }

function UI:Select(key, auto)
  self.selected, self.autoKey = key, auto and key or nil
end

local function DimText(text) return C.dim .. text .. "|r" end
local function WarnText(text) return C.warn .. text .. "|r" end
local function SugCount(d) return d.suggestions and #d.suggestions or 0 end
local function NoneTip() return L.MEMBER_TIP_NONE, 0.7, 0.7, 0.7 end

local MEMBER_STATE = {
  uninspected = {
    line = function() return DimText(L.MEMBER_TIP_NOT_INSPECTED) end,
    tip = function() return L.MEMBER_TIP_NOT_INSPECTED, 0.7, 0.7, 0.7 end,
  },
  browse = {
    line = function(d) return C.browse .. string.format(L.MEMBER_LINE_BROWSE, SugCount(d)) .. "|r" end,
    tip = function(d) return string.format(L.MEMBER_TIP_BROWSE, ProfName(d.prof), SugCount(d)), 0.7, 0.7, 0.7 end,
  },
  best = {
    line = function(d)
      local n = d.knownCount or 0
      if n == 1 then return string.format(L.MEMBER_LINE_UPGRADES_1, n, ShortSlotName(d.best.slot)) end
      return string.format(L.MEMBER_LINE_UPGRADES, n, ShortSlotName(d.best.slot))
    end,
    tip = function(d) return string.format(L.MEMBER_TIP_BEST, d.knownCount or 0, GainText(d.best)), 0.3, 1, 0.3 end,
  },
  ["no-spec"] = {
    line = function() return WarnText(L.MEMBER_LINE_NOSPEC) end,
    tip = function() return L.MEMBER_TIP_NOSPEC, 1, 0.5, 0.2 end,
  },
  ["no-level"] = {
    line = function() return WarnText(L.MEMBER_LINE_NOLEVEL) end,
    tip = function() return L.MEMBER_TIP_NOLEVEL, 1, 0.5, 0.2 end,
  },
  loading = { line = function() return DimText(L.MEMBER_LINE_LOADING) end, tip = NoneTip },
  none = { line = function() return DimText(L.MEMBER_LINE_NONE) end, tip = NoneTip },
}

local function MemberState(d) return MEMBER_STATE[GCA.MemberStatus(d)] end

local function MemberLine(d) return MemberState(d).line(d) end
UI.MemberLine = MemberLine

local function LevelLine(d)
  local status = d.isSelf and "" or (d.online and G("FRIENDS_LIST_ONLINE") or (C.offline .. G("FRIENDS_LIST_OFFLINE") .. "|r"))
  return string.format(L.MEMBER_TIP_LEVEL, G("LEVEL"), tostring(d.level or "?"), ClassName(d.class)) .. (status ~= "" and ("  ·  " .. status) or "")
end

local function MemberTip(self)
  local d = self.data
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(d.key, ClassColor(d.class))
  GameTooltip:AddLine(LevelLine(d), 1, 1, 1)
  GameTooltip:AddLine(MemberLine(d), SUB_TINT[1], SUB_TINT[2], SUB_TINT[3])
  if d.member then
    GameTooltip:AddLine(string.format(L.MEMBER_TIP_GEAR, SourceText(d.member, d.isSelf), Ago(d.member.time)), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(string.format(L.MEMBER_TIP_SPEC, SpecHowText(d)), 1, 1, 1)
  end
  GameTooltip:AddLine(MemberState(d).tip(d))
  if d.member and not d.isSelf then GameTooltip:AddLine(L.MEMBER_TIP_FORGET, 0.5, 0.5, 0.5) end
  GameTooltip:Show()
end

local function MemberGain(d)
  if d.browse or not d.best then return "" end
  return UI.GainNum(d.best.points)
end
UI.MemberGain = MemberGain

UI.MEMBER_GAIN_W = 46
local MEMBER_TEXT_X = 22
local function CreateMemberRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(MEMBER_ROW_H)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  UI.AddRowArt(b)
  b.gain = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.gain:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.gain:SetWidth(UI.MEMBER_GAIN_W)
  b.gain:SetJustifyH("RIGHT")
  GainFont(b.gain)
  SingleLine(b.gain)
  b.name = UI.RowFont(b:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
  b.name:SetPoint("LEFT", b, "LEFT", MEMBER_TEXT_X, 0)
  b.name:SetJustifyH("LEFT")
  SingleLine(b.name)
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" and IsShiftKeyDown() and self.data.member and not self.data.isSelf then
      GCA:ForgetGear(self.data.key)
      GCA:Print(string.format(L.FORGOT, self.data.key))
    else
      UI:SelectMember(self.data.key)
    end
    GCA:RefreshUI()
  end)
  SetTip(b, "member row", MemberTip)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

function UI.StatusDot(online)
  return online and "|TInterface\\FriendsFrame\\StatusIcon-Online:12:12:0:0|t"
    or "|TInterface\\FriendsFrame\\StatusIcon-Offline:12:12:0:0|t"
end
function UI.OfflineColor(r, g, b)
  local l = 0.3 * r + 0.59 * g + 0.11 * b
  return (r + l) * 0.4, (g + l) * 0.4, (b + l) * 0.4
end
function UI.MemberName(m)
  local online = m.online or m.isSelf
  local r, g, b = ClassColor(m.class)
  if not online then r, g, b = UI.OfflineColor(r, g, b) end
  return UI.StatusDot(online) .. " " .. Hex(r, g, b) .. tostring(m.key or "?") .. "|r"
end

local function UpdateMemberRow(b, d, listW)
  local offline = not d.online and not d.isSelf
  b.name:SetText(UI.MemberName(d) .. "  " .. C.muted .. tostring(d.level or "?") .. "|r"
    .. (d.isSelf and (" " .. C.dim .. "(" .. L.YOU .. ")|r") or ""))
  b.gain:SetText(MemberGain(d))
  local textW = math.max(40, listW - MEMBER_TEXT_X - UI.MEMBER_GAIN_W - 10)
  b.name:SetWidth(textW)
  b.textW = textW
  b.name:SetAlpha(1)
  b.gain:SetAlpha((d.best and d.best.future) and 0.55 or 1)
  local on = UI.selected == d.key
  b.sel:SetShown(on)
  b.offline = offline
end

function UI.MemberRows(members, query)
  local online, offline = GCA.ListedMembers(members, query)
  local out = {}
  local function group(key, list)
    if #list == 0 then return end
    out[#out + 1] = { rowKind = "group", group = key, count = #list, list = "members" }
    if not UI.collapsed[key] then for _, e in ipairs(list) do out[#out + 1] = e end end
  end
  group("online", online)
  group("offline", offline)
  return out
end

local GROUP_TIP = { online = "GROUP_TIP_ONLINE", offline = "GROUP_TIP_OFFLINE" }
local function GroupLabel(key)
  if key == "online" then return G("FRIENDS_LIST_ONLINE") end
  return G("FRIENDS_LIST_OFFLINE")
end

local function GroupTip(self)
  local d = self.data
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(GroupLabel(d.group) .. " (" .. tostring(d.count) .. ")", 1, 1, 1)
  GameTooltip:AddLine(L[GROUP_TIP[d.group] or "GROUP_TIP_OFFLINE"], nil, nil, nil, true)
  GameTooltip:Show()
end

local function CreateGroupRow(parent)
  local b = UI.CreateCategoryRow(parent, function(self)
    local d = self.data
    UI.collapsed[d.group] = not UI.collapsed[d.group]
    UI:RefreshMemberList()
  end)
  SetTip(b, "group header", GroupTip)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function UpdateGroupRow(b, d, listW)
  b:SetCategory(GroupLabel(d.group), not UI.collapsed[d.group], listW)
end

P.CreateGroupRow = CreateGroupRow
P.CreateMemberRow = CreateMemberRow
P.MEMBER_TEXT_X = MEMBER_TEXT_X
P.UpdateGroupRow = UpdateGroupRow
P.UpdateMemberRow = UpdateMemberRow
