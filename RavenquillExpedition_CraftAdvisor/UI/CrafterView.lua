local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local Label, SetTip, ProfName, Ago, Hex, ClassColor = P.Label, P.SetTip, P.ProfName, P.Ago, P.Hex, P.ClassColor
local LEFT_W, RIGHT_X, RightW = P.LEFT_W, P.RIGHT_X, P.RightW
local PANEL_TOP, PANEL_BOTTOM, DETAIL_HEAD, MEMBER_LIST_TOP = P.PANEL_TOP, P.PANEL_BOTTOM, P.DETAIL_HEAD, P.MEMBER_LIST_TOP
local CreateScrollList = RavenquillExpedition.CreateScrollList
local ALL = "*"

UI.RECIPE_SEARCH_W = 200
UI.crafterUpgradesOnly = false

function UI.AllCollapsed()
  local t = {}
  for _, p in ipairs(GCA.PROFESSIONS) do t[p.key] = true end
  return t
end
UI.crafterCollapsed = UI.AllCollapsed()

function UI:SelectCrafter(key)
  UI.crafterSel = key
  UI.crafterCollapsed = key and {} or UI.AllCollapsed()
  self:RefreshCrafters()
end

function UI:SetUpgradesOnly(on)
  UI.crafterUpgradesOnly = on and true or false
  UI.crafterCollapsed = {}
  self:RefreshCrafters()
end

local Build = {}

function Build.ListPanel(self, cv, painted, listH)
  local inset = P.NewInset(cv, painted)
  inset:SetPoint("TOPLEFT", 10, PANEL_TOP)
  inset:SetSize(LEFT_W, listH)
  self.crafterInset = inset
  self.crafterSearch = P.CreateSearchBox(inset, LEFT_W - 26, L.CRAFTERS_SEARCH, L.CRAFTERS_SEARCH_TIP,
    function() UI:RefreshCrafters() end)
  self.crafterSearch:SetPoint("TOPLEFT", inset, "TOPLEFT", 13, -8)
  self.crafterList = CreateScrollList(inset, LEFT_W - 30, listH - MEMBER_LIST_TOP - 5, UI.CRAFTER_LIST_KINDS)
  self.crafterList:SetPoint("TOPLEFT", 5, -MEMBER_LIST_TOP)
  P.RaiseInsetBorder(inset, self.crafterList)
end

local function UpgradesTip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(L.CRAFTERS_UPGRADES_ONLY, 1, 1, 1)
  GameTooltip:AddLine(L.CRAFTERS_UPGRADES_TIP, nil, nil, nil, true)
  GameTooltip:Show()
end

function Build.UpgradesToggle(self, md)
  local chk = P.NewCheck(md, 22)
  chk:SetPoint("TOPLEFT", md, "TOPLEFT", 14 + UI.RECIPE_SEARCH_W + 16, -49)
  chk:SetScript("OnClick", function(b) UI:SetUpgradesOnly(b:GetChecked()) end)
  SetTip(chk, "upgrades only", UpgradesTip)
  chk:SetScript("OnLeave", GameTooltip_Hide)
  chk.label = Label(md, "GameFontHighlightSmall")
  chk.label:SetPoint("LEFT", chk, "RIGHT", 4, 0)
  chk.label:SetText(L.CRAFTERS_UPGRADES_ONLY)
  self.upgradesOnly = chk
end

function Build.Header(self, md)
  self.crafterName = Label(md, "GameFontNormalLarge")
  self.crafterName:SetPoint("TOPLEFT", md, "TOPLEFT", 14, -10)
  self.crafterSub = Label(md, "GameFontHighlightSmall")
  self.crafterSub:SetPoint("TOPLEFT", md, "TOPLEFT", 14, -32)
  self.recipeSearch = P.CreateSearchBox(md, UI.RECIPE_SEARCH_W, L.RECIPES_SEARCH, L.RECIPES_SEARCH_TIP, function()
    UI.crafterCollapsed = {}
    UI:RefreshCrafters()
  end)
  self.recipeSearch:SetPoint("TOPLEFT", md, "TOPLEFT", 14, -50)
  Build.UpgradesToggle(self, md)
end

function Build.RecipePanel(self, md, listH, rw)
  local area = CreateFrame("Frame", nil, md)
  area:SetPoint("TOPLEFT", md, "TOPLEFT", 6, -DETAIL_HEAD)
  area:SetSize(rw - 8, listH - DETAIL_HEAD - 6)
  self.recipeArea = area
  self.recipeList = CreateScrollList(area, rw - 42, listH - DETAIL_HEAD - 16, UI.RECIPE_KINDS)
  self.recipeList:SetPoint("TOPLEFT", 5, -5)
  self.recipeEmpty = area:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  self.recipeEmpty:SetPoint("CENTER")
  self.recipeEmpty:SetWidth(rw - 68)
  P.RaiseInsetBorder(md, self.recipeList)
end

function UI:BuildCrafterView(c, painted, listH, rw)
  local cv = CreateFrame("Frame", nil, c)
  cv:SetAllPoints(c)
  self.crafterView = cv
  Build.ListPanel(self, cv, painted, listH)
  local md = CreateFrame("Frame", nil, cv)
  md:SetPoint("TOPLEFT", RIGHT_X - 4, PANEL_TOP)
  md:SetSize(rw + 4, listH)
  UI.AddDetailBorder(md)
  self.crafterDetail = md
  Build.Header(self, md)
  Build.RecipePanel(self, md, listH, rw)
  return cv
end

function UI:LayoutCrafters(w, h)
  if not self.crafterList then return end
  local listH, dw = h + PANEL_TOP - PANEL_BOTTOM, RightW(w) + 4
  local iw, ih = dw - 12, listH - DETAIL_HEAD - 6
  self.crafterInset:SetSize(LEFT_W, listH)
  self.crafterList:Resize(LEFT_W - 30, listH - MEMBER_LIST_TOP - 5, true)
  self.crafterDetail:SetSize(dw, listH)
  self.crafterName:SetWidth(dw - 28)
  self.crafterSub:SetWidth(dw - 28)
  self.recipeArea:SetSize(iw, ih)
  self.recipeList:Resize(iw - 34, ih - 10, true)
  self.recipeEmpty:SetWidth(iw - 60)
end

local function Trim(s)
  return (tostring(s or ""):match("^%s*(.-)%s*$")) or ""
end

local function FindCrafter(roster, key)
  for _, e in ipairs(roster) do
    if e.key == key then return e end
  end
end

function UI.CrafterListRows(roster, query)
  local out = { { rowKind = "all", count = #roster } }
  for _, e in ipairs(roster) do
    if GCA.MatchesSearch(e.key, query) then out[#out + 1] = e end
  end
  return out
end

local function ProfLine(entry)
  local parts = {}
  for i, p in ipairs(entry.profs) do parts[i] = UI.ProfIcon(p.prof) .. " " .. ProfName(p.prof) .. " " .. p.rank end
  return table.concat(parts, "  ·  ")
end

local function HeaderTexts(roster, sel, nRecipes)
  if sel then
    return Hex(ClassColor(sel.class)) .. sel.key .. "|r",
      string.format(L.CRAFTERS_MEMBER_SUB, ProfLine(sel), UI.CrafterStatus(sel.online), Ago(sel.time))
  end
  local online = 0
  for _, e in ipairs(roster) do
    if e.online then online = online + 1 end
  end
  return L.CRAFTERS_ALL, string.format(L.CRAFTERS_ALL_SUB, #roster, online, nRecipes)
end

local function EmptyText(roster, sel, nRecipes, shown, query)
  if #roster == 0 then return L.CRAFTERS_EMPTY end
  if nRecipes == 0 then return sel and string.format(L.CRAFTERS_NO_RECIPES, sel.key) or L.CRAFTERS_NO_RECIPES_ALL end
  if shown > 0 then return "" end
  if query ~= "" then return string.format(L.CRAFTERS_NO_MATCH, query) end
  return L.CRAFTERS_NO_UPGRADES
end

local function CurrentCrafter(roster)
  local sel = UI.crafterSel and FindCrafter(roster, UI.crafterSel)
  if UI.crafterSel and not sel then UI.crafterSel, UI.crafterCollapsed = nil, UI.AllCollapsed() end
  return sel or nil
end

local function ShowRecipes(self, roster, sel)
  local rows = GCA:CrafterRecipes(UI.crafterSel)
  local query = Trim(self.recipeSearch:GetText())
  local data, shown = UI.CrafterRecipeRows(rows, query, UI.crafterUpgradesOnly)
  self.recipeList:SetData(data)
  self.recipeEmpty:SetText(EmptyText(roster, sel, #rows, shown, query))
  local name, sub = HeaderTexts(roster, sel, #rows)
  self.crafterName:SetText(name)
  self.crafterSub:SetText(sub)
  local key = UI.crafterSel or ALL
  if self.recipeKey ~= key then
    self.recipeKey = key
    self.recipeList:ScrollTo(0)
  end
end

function UI:RefreshCrafters()
  if not (self.crafterList and self.frame) then return end
  local roster = GCA:CrafterRoster()
  local sel = CurrentCrafter(roster)
  self.crafterList:SetData(UI.CrafterListRows(roster, self.crafterSearch:GetText() or ""))
  self.upgradesOnly:SetChecked(UI.crafterUpgradesOnly)
  ShowRecipes(self, roster, sel)
end
