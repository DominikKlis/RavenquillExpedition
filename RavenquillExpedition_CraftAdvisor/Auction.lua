-- Auctionator integration (user 2026-11-15): "Zum herstellen" (cost to craft) and "Gewinn" (profit) for a craft,
-- from Auctionator's price data, computed exactly as Auctionator's own crafting info in the profession window
-- (Auctionator Source_Classic/CraftingInfo/Main.lua): per reagent the vendor price, else the auction price, times
-- the count; profit = the crafted item's auction price x the AH cut (Auctionator.Constants.AfterAHCut) - cost.
-- Only through Auctionator's public API (Auctionator.API.v1); without Auctionator (or with a broken/renamed one)
-- everything here returns nil and the UI shows nothing.
local _, ns = ...
local GCA = ns.GCA

local A = {}
GCA.Auction = A

A.CALLER = "Ravenquill Craft Advisor" -- Auctionator's API wants a caller ID string
A.AH_CUT = 0.95                         -- fallback when Auctionator.Constants.AfterAHCut is missing

local function API()
  local a = rawget(_G, "Auctionator")
  local api = type(a) == "table" and type(a.API) == "table" and a.API.v1
  if type(api) ~= "table" or type(api.GetAuctionPriceByItemID) ~= "function" then return nil end
  return api
end

-- true when Auctionator is installed and loaded (its API is there)
function A.Available() return API() ~= nil end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, A.CALLER, ...)
  if ok and type(v) == "number" and v >= 0 then return v end
  return nil
end

-- unit price of one item: vendor price first (Auctionator's order), else the last auction price; nil = unknown
function A.UnitPrice(itemID)
  local api = API()
  if not api or type(itemID) ~= "number" then return nil end
  return call(api.GetVendorPriceByItemID, itemID) or call(api.GetAuctionPriceByItemID, itemID)
end

function A.AuctionPrice(itemID)
  local api = API()
  if not api or type(itemID) ~= "number" then return nil end
  return call(api.GetAuctionPriceByItemID, itemID)
end

-- regs = recipe reagents { {itemID, count}, ... }. Returns total copper, number of reagents without a price
-- (Auctionator counts those as 0 too), or nil without Auctionator / reagents.
function A.CraftCost(regs)
  if not API() or type(regs) ~= "table" or #regs == 0 then return nil end
  local total, missing = 0, 0
  for _, reg in ipairs(regs) do
    local unit = A.UnitPrice(reg[1])
    if unit then total = total + unit * (reg[2] or 1) else missing = missing + 1 end
  end
  return math.floor(total + 0.5), missing
end

-- profit of crafting itemID (count made, default 1) for cost copper: nil without an auction price for the item
function A.Profit(itemID, cost, made)
  local price = A.AuctionPrice(itemID)
  if not price or not cost then return nil end
  local a = rawget(_G, "Auctionator")
  local cut = type(a) == "table" and type(a.Constants) == "table" and tonumber(a.Constants.AfterAHCut) or A.AH_CUT
  return math.floor(price * (made or 1) * cut - cost)
end
