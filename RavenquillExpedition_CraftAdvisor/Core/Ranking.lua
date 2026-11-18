local _, ns = ...
local GCA = ns.GCA
local PlainCall, Scoring = GCA.PlainCall, ns.Scoring
local EMPTY = {}

local function Better(a, b)
  if a.tier ~= b.tier then return a.tier < b.tier end
  if math.abs(a.points - b.points) > 1e-9 then return a.points > b.points end
  if a.known ~= b.known then return a.known end
  if (a.kind == "enchant") ~= (b.kind == "enchant") then return b.kind == "enchant" end
  return a.slot < b.slot
end
GCA.BetterSuggestion = Better

local function Order(a, b)
  if a.tier ~= b.tier then return a.tier < b.tier end
  local fa, fb = a.future and true or false, b.future and true or false
  if fa ~= fb then return fb end
  return Better(a, b)
end
GCA.SuggestionOrder = Order

GCA.TIER_PARTNER = 2

local function OtherFaction(row, faction)
  return row.faction and faction and row.faction ~= faction
end
function GCA.Offerable(known, showAll, row, faction)
  if known then return true end
  return showAll and not OtherFaction(row, faction)
end
function GCA.KeepSuggestion(best, all, bestKey, group, sug)
  local cur = best[bestKey]
  if not cur or Better(sug, cur) then best[bestKey] = sug end
  if not all then return end
  local rows = all[group] or {}
  all[group] = rows
  rows[#rows + 1] = sug
end

function GCA.PlayerFaction()
  return PlainCall("string", UnitFactionGroup, "player")
end

function GCA:PairInfo(mh, oh)
  local stats = {}
  for k, v in pairs(mh.cstats or EMPTY) do stats[k] = v end
  local off = Scoring.inOffHand({ stats = oh.cstats or EMPTY })
  for k, v in pairs(off.stats or EMPTY) do stats[k] = (stats[k] or 0) + v end
  return { name = (mh.name or "?") .. " + " .. (oh.name or "?"), quality = mh.quality, icon = mh.icon, link = mh.link,
    cstats = stats, speed = mh.speed, pair = { mh, oh } }
end

local function SearchKey(query)
  return tostring(query or ""):lower():match("^%s*(.-)%s*$") or ""
end

local function Matches(text, q)
  return q == "" or tostring(text):lower():find(q, 1, true) ~= nil
end

local function MatchingRows(g, q)
  if Matches(g.sug.info and g.sug.info.name or "", q) then return g.rows end
  local rows = {}
  for _, r in ipairs(g.rows) do
    if Matches(r.member.key, q) then rows[#rows + 1] = r end
  end
  return rows
end

local function CountNewMembers(rows, seen)
  local n = 0
  for _, r in ipairs(rows) do
    if not seen[r.member.key] then seen[r.member.key] = true; n = n + 1 end
  end
  return n
end

function GCA:MatchNeeds(needs, query, withOffline)
  local q = SearchKey(query)
  local groups = needs and (withOffline and needs.craftsAll or needs.crafts) or EMPTY
  local matched, seen, members = {}, {}, 0
  for _, g in ipairs(groups) do
    local rows = MatchingRows(g, q)
    if #rows > 0 then
      members = members + CountNewMembers(rows, seen)
      matched[#matched + 1] = { group = g, rows = rows, cat = self.SECTION_OF[g.sug.slot] or g.sug.slot }
    end
  end
  return matched, members, CountNewMembers(needs and needs.offline or EMPTY, {})
end

function GCA.MatchesSearch(text, query)
  return Matches(text, SearchKey(query))
end

function GCA.ListedMembers(members, query)
  local q = SearchKey(query)
  local online, offline = {}, {}
  for _, e in ipairs(members or EMPTY) do
    if (e.isSelf or e.member) and Matches(e.key, q) then
      if e.isSelf or e.online then online[#online + 1] = e else offline[#offline + 1] = e end
    end
  end
  return online, offline
end

function GCA.DefaultMember(members)
  for _, e in ipairs(members) do
    if not e.isSelf and e.best then return e end
  end
end

local LISTED_STATE = { ["no-spec"] = "no-spec", ["no-level"] = "no-level", loading = "loading" }
function GCA.MemberStatus(e)
  if not e.member then return "uninspected" end
  if e.browse then return "browse" end
  if e.best then return "best" end
  return LISTED_STATE[e.state] or "none"
end

local UNSCORED = { ["no-spec"] = "no-spec", ["no-level"] = "no-level", ["no-weights"] = "no-weights", ["no-class"] = "no-weights" }
function GCA:EmptyReason(e, count, prof, browse)
  if not e.member then return "no-gear" end
  if UNSCORED[e.state] then return UNSCORED[e.state] end
  if count > 0 then return nil end
  if (e.pending or 0) > 0 then return "loading" end
  if browse then return "browse" end
  if self:KnownCount(prof) == 0 then return "no-known" end
  return "none"
end
