local _, ns = ...
local GCA = ns.GCA

local A = {}
GCA.Auction = A

A.CALLER = "Ravenquill Craft Advisor"
A.AH_CUT = 0.95

local function API()
  local a = rawget(_G, "Auctionator")
  local api = type(a) == "table" and type(a.API) == "table" and a.API.v1
  if type(api) ~= "table" or type(api.GetAuctionPriceByItemID) ~= "function" then return nil end
  return api
end

function A.Available() return API() ~= nil end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, A.CALLER, ...)
  if ok and type(v) == "number" and v >= 0 then return v end
  return nil
end

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

function A.CraftCost(regs)
  if not API() or type(regs) ~= "table" or #regs == 0 then return nil end
  local total, missing = 0, 0
  for _, reg in ipairs(regs) do
    local unit = A.UnitPrice(reg[1])
    if unit then total = total + unit * (reg[2] or 1) else missing = missing + 1 end
  end
  return math.floor(total + 0.5), missing
end

function A.Profit(itemID, cost, made)
  local price = A.AuctionPrice(itemID)
  if not price or not cost then return nil end
  local a = rawget(_G, "Auctionator")
  local cut = type(a) == "table" and type(a.Constants) == "table" and tonumber(a.Constants.AfterAHCut) or A.AH_CUT
  return math.floor(price * (made or 1) * cut - cost)
end
