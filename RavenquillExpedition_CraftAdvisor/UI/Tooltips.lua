local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local ClassColor, Hex = P.ClassColor, P.Hex

-- K17 (user, 2026-11-14: "it says way too much ... nothing extra"): hovering an item anywhere in the window shows ONLY
-- the plain Blizzard tooltip (SetHyperlink / SetItemByID; an enchant = its spell's tooltip). Gain, stat breakdown, set
-- hints, sources, "replaces", level notes and Offer explanations are in the rows / detail panel / sheet, not here.
-- Non-item tooltips (buttons, filter, spec, search, Offer, crafted box, source buttons) keep their texts.
function UI.PlainItemTip(owner, link, itemID, name, spellID)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local shown = false
  if type(link) == "string" and link:find("item:", 1, true) then
    shown = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
  end
  if not shown and itemID and GameTooltip.SetItemByID then shown = pcall(GameTooltip.SetItemByID, GameTooltip, itemID) end
  if not shown and spellID and GameTooltip.SetSpellByID then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, spellID) end
  if not shown then GameTooltip:SetText(name or "?") end
  GameTooltip:Show()
end

-- User 2026-11-15: hovering a craft compares it with what THAT member wears (not your own gear). The member's worn
-- item(s) go into the client's compare tooltips (ShoppingTooltip1/2) with "Equipped by <name>" on top; an empty
-- slot = one compare tooltip saying so. Blizzard's own comparison (Shift / "always compare") would put your gear
-- there: GameTooltip_ShowCompareItem and the compare tooltips' OnShow are hooked to put the member's back while
-- one of our item tooltips is up. UI.compare = { owner, list = { worn infos }, who, empty } of the open tooltip.
function UI.CompareTips()
  return { ShoppingTooltip1, ShoppingTooltip2 }
end
function UI.HideCompare()
  UI.compare = nil
  for _, tip in ipairs(UI.CompareTips()) do if tip and tip.Hide then pcall(tip.Hide, tip) end end
end
function UI.FillCompare()
  local c = UI.compare
  if not c or c.filling or not ShoppingTooltip1 then return end
  local okOwner, isOurs = pcall(function() return GameTooltip:IsShown() and (not GameTooltip.GetOwner or GameTooltip:GetOwner() == c.owner) end)
  if not (okOwner and isOurs) then return end
  c.filling = true
  local tips, used = UI.CompareTips(), {}
  local head = string.format(L.COMPARE_WORN_BY, c.who)
  local function fill(tip, x)
    tip:SetOwner(GameTooltip, "ANCHOR_NONE")
    local shown = false
    if x and type(x.link) == "string" and x.link:find("item:", 1, true) then shown = pcall(tip.SetHyperlink, tip, x.link) end
    if not shown then tip:SetText(x and x.name or L.SLOT_EMPTY_COMPARE, 1, 1, 1) end
    tip:AddLine(head, 1, 0.82, 0)
    tip:Show()
    used[#used + 1] = tip
  end
  pcall(function()
    if c.empty then
      if tips[1] then fill(tips[1], nil) end
    else
      for i, x in ipairs(c.list) do if tips[i] then fill(tips[i], x) end end
    end
    for i = #used + 1, #tips do if tips[i] then tips[i]:Hide() end end
    -- right of the item tooltip, or left when there is no room (as GearQuestForever)
    local total = 0
    for _, t in ipairs(used) do total = total + (t:GetWidth() or 0) end
    local right = GameTooltip:GetRight() or 0
    local screen = (UIParent and UIParent:GetRight()) or right
    local point, rel = "TOPLEFT", "TOPRIGHT"
    if right + total > screen - 8 then point, rel = "TOPRIGHT", "TOPLEFT" end
    local anchor = GameTooltip
    for _, t in ipairs(used) do
      t:ClearAllPoints()
      t:SetPoint(point, anchor, rel, 0, 0)
      anchor = t
    end
  end)
  c.filling = false
end
function UI.ShowWornCompare(owner, d, cur)
  UI.compare = nil
  if not (d and cur and d.kind ~= "enchant") then return end
  local list = {}
  local eq = d.equipped
  if eq and eq.pair then list = { eq.pair[1], eq.pair[2] } elseif eq then list = { eq } end
  local r, g, b = ClassColor(cur.class)
  UI.compare = { owner = owner, list = list, empty = #list == 0, who = Hex(r, g, b) .. tostring(cur.key or "?") .. "|r" }
  UI.FillCompare()
end
function UI.HookCompare()
  if UI.compareHooked then return end
  UI.compareHooked = true
  if hooksecurefunc and type(GameTooltip_ShowCompareItem) == "function" then
    pcall(hooksecurefunc, "GameTooltip_ShowCompareItem", function() UI.FillCompare() end)
  end
  for _, tip in ipairs(UI.CompareTips()) do
    if tip and tip.HookScript then pcall(tip.HookScript, tip, "OnShow", function() UI.FillCompare() end) end
  end
  if GameTooltip.HookScript then pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function() if UI.compare then UI.HideCompare() end end) end
end

-- a suggestion (craft or enchant) row/card: the crafted item's (or the enchant spell's) plain tooltip; for an item
-- the member's worn item(s) beside it (UI.ShowWornCompare)
local function ShowSuggestionTooltip(owner, d, cur)
  if not (d and d.info) then return end
  UI.HookCompare()
  if d.kind == "enchant" then
    UI.PlainItemTip(owner, nil, nil, d.info.name, d.cand and d.cand.spellID)
  else
    UI.PlainItemTip(owner, d.info.link, d.cand and d.cand.itemID, d.info.name)
  end
  UI.AddStatChanges(d, cur)
  UI.ShowWornCompare(owner, d, cur)
end

-- User 2026-11-15: under the item tooltip, the stats the member gains (green) and loses (red) against what they
-- wear now (UI.StatDiff: the same canonical stats the score uses). Nothing when a side has no stat data.
function UI.AddStatChanges(d, cur)
  local rows = UI.StatDiff(d)
  if not rows or #rows == 0 then return end
  GameTooltip:AddLine(" ")
  local who = cur and cur.key
  if who then
    local r, g, b = ClassColor(cur.class)
    GameTooltip:AddLine(string.format(L.TIP_CHANGES_FOR, Hex(r, g, b) .. who .. "|r"), 1, 0.82, 0)
  else
    GameTooltip:AddLine(L.TIP_CHANGES, 1, 0.82, 0)
  end
  for _, row in ipairs(rows) do
    if row.amount < 0 then
      GameTooltip:AddLine(UI.StatText(row), 1, 0.13, 0.13)
    else
      GameTooltip:AddLine(UI.StatText(row), 0.12, 1, 0.12)
    end
  end
  GameTooltip:Show()
end
UI.ShowSuggestionTooltip = ShowSuggestionTooltip

-- shared with the files loaded after this one (P)
P.ShowSuggestionTooltip = ShowSuggestionTooltip
