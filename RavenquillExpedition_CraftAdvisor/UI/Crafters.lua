local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local C, FirstName, SlotName = P.C, P.FirstName, P.SlotName
local EMPTY = {}
local MAX_LISTED = 8
C.crafter, C.crafterOff = "|cff66dd88", "|cff9d9d9d"

function UI.GuildCrafters(d, cur)
  if not (d and d.cand and cur and (cur.isSelf or cur.browse)) or d.known then return EMPTY end
  return GCA:CraftersOf(cur.prof or GCA:SelectedProfession(), d.cand.spellID)
end

local function Status(c) return c.online and L.CRAFTER_ONLINE or L.CRAFTER_OFFLINE end

function UI.CrafterBadge(d, cur)
  local list = UI.GuildCrafters(d, cur)
  local first = list[1]
  if not first then return nil end
  local text = string.format(L.CRAFTED_BY, FirstName(first.key) .. " (" .. Status(first) .. ")")
  if #list > 1 then text = text .. " " .. string.format(L.CRAFTED_BY_MORE, #list - 1) end
  return (first.online and C.crafter or C.crafterOff) .. text .. "|r"
end

function UI.AskTarget(cur, d)
  if not (cur and cur.isSelf) then return nil end
  local first = UI.GuildCrafters(d, cur)[1]
  return first and first.online and first or nil
end

function UI.RowAction(cur, d)
  if UI.CanOffer(cur, d) then return "offer" end
  if UI.AskTarget(cur, d) then return "ask" end
  return nil
end

function UI.ShowRowAction(button, cur, d)
  local action = UI.RowAction(cur, d)
  button:SetShown(action ~= nil)
  if action then button:SetText(action == "ask" and L.ASK or L.OFFER) end
  return action ~= nil
end

local function AskMessage(d, who, item)
  local t = d.kind == "enchant" and L.WHISPER_ASK_ENCHANT or L.WHISPER_ASK_CRAFT
  return UI.FillTemplate(t, { item = item, slot = SlotName(d.slot), name = FirstName(who) })
end

function UI.AskText(d, who)
  local name = d.info.name or (d.enchant and d.enchant.name)
  local msg = AskMessage(d, who, d.kind ~= "enchant" and d.info.link or name)
  if #msg > UI.WHISPER_MAX and name then msg = AskMessage(d, who, name) end
  return UI.Utf8Cut(msg, UI.WHISPER_MAX)
end

function UI.DoAsk(d, cur)
  local target = UI.AskTarget(cur, d)
  if not target then return false end
  local msg = UI.AskText(d, target.key)
  if IsShiftKeyDown() then P.SendWhisper(target.key, msg, string.format(L.ASK_SENT, target.key)) else P.OpenWhisper(target.key, msg) end
  return true
end

local ON_RGB, OFF_RGB = { 0.4, 0.87, 0.53 }, { 0.6, 0.6, 0.6 }
local function AddCrafterLine(c)
  local rgb, left = c.online and ON_RGB or OFF_RGB, c.online and 1 or 0.6
  GameTooltip:AddDoubleLine(c.key, Status(c), left, left, left, rgb[1], rgb[2], rgb[3])
end

function UI.AddCrafterLines(d, cur)
  local list = UI.GuildCrafters(d, cur)
  if not list[1] then return end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(L.CRAFTERS_HEAD, 1, 0.82, 0)
  for i = 1, math.min(#list, MAX_LISTED) do AddCrafterLine(list[i]) end
  if #list > MAX_LISTED then GameTooltip:AddLine(string.format(L.CRAFTERS_MORE, #list - MAX_LISTED), 0.6, 0.6, 0.6) end
end

function UI.AskTip(owner, d, cur)
  local target = UI.AskTarget(cur, d)
  if not target then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(L.ASK, 1, 1, 1)
  GameTooltip:AddLine(string.format(L.ASK_TIP, FirstName(target.key)), 1, 0.82, 0)
  GameTooltip:AddLine(L.OFFER_TIP_CLICK, 1, 1, 1)
  GameTooltip:AddLine(L.OFFER_TIP_SHIFT, 1, 1, 1)
  UI.AddCrafterLines(d, cur)
  GameTooltip:Show()
end
