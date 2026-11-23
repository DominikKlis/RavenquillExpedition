local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local SafeCall, Plain, IsSecret = GS.SafeCall, GS.Plain, GS.IsSecret
local Own, Act, MyLevel, Diag = ns.Own, ns.Act, ns.MyLevel, ns.Diag

H.EPIC_MOUNT_SPEED = 13
H.MOUNT_MIN_SPEED = 7.5
H.MOUNT_TIER_LEVEL = { 40, 60 }
H.REP_MILESTONE = 8
H.SKILL_TOP = 300
H.DUEL_EVERY = 86400
H.PVP_FIRST_RANK_INDEX = 5

local function Store(key)
  local t = H.cdb[key]
  if type(t) ~= "table" then t = {}; H.cdb[key] = t end
  return t
end

local function Report(k, fields, highlight)
  if highlight then H:Add(Own(k, fields), "self") else H:Activity(Act(k, fields)) end
end

local patterns = {}
local function Match(text, global)
  local p = patterns[global]
  if p == nil then
    p = GS.FormatToPattern(_G[global]) or false
    patterns[global] = p
  end
  if p then return text:match(p) end
end

local function FactionStanding(R, i)
  local f = SafeCall(R.GetFactionDataByIndex, i)
  if type(f) ~= "table" or IsSecret(f) or Plain(f.isHeader) then return end
  return Plain(f.name, "string"), Plain(f.reaction, "number")
end

local function CurrentStandings()
  local R = C_Reputation
  local n = R and Plain(SafeCall(R.GetNumFactions), "number") or 0
  if n == 0 then return end
  local out = {}
  for i = 1, n do
    local name, standing = FactionStanding(R, i)
    if name and standing then out[name] = standing end
  end
  return out
end

local function CurrentPvpRank()
  if not (UnitPVPRank and GetPVPRankInfo) then return end
  local index = Plain(SafeCall(UnitPVPRank, "player"), "number")
  if not index then return end
  if index < H.PVP_FIRST_RANK_INDEX then return 0 end
  local name, number = SafeCall(GetPVPRankInfo, index, "player")
  return Plain(number, "number") or index - H.PVP_FIRST_RANK_INDEX + 1, Plain(name, "string")
end

local function CheckPvpRank()
  local number, name = CurrentPvpRank()
  if not number then return end
  local had = H.cdb.pvpRank
  if had ~= nil and number <= had then return end
  H.cdb.pvpRank = number
  if had ~= nil then Report("pvp", { pk = "rank", pr = number, name = name }, true) end
end

local mountRecordMadeNow = false

function H:SeedMilestones()
  if type(self.cdb.mount) ~= "table" then
    self.cdb.mount = { tier = 0, base = MyLevel() or 99 }
    mountRecordMadeNow = true
  end
  if type(self.cdb.reps) ~= "table" then self.cdb.reps = CurrentStandings() end
  CheckPvpRank()
end

function H:EndMountSeeding()
  local rec = self.cdb.mount
  if rec and not mountRecordMadeNow then rec.base = nil end
end

local function MountTier()
  if not Plain(SafeCall(IsMounted)) or Plain(SafeCall(UnitOnTaxi, "player")) or GS:InInstance() then return end
  local _, run = SafeCall(GetUnitSpeed, "player")
  run = Plain(run, "number")
  if not run or run <= H.MOUNT_MIN_SPEED then return end
  return run >= H.EPIC_MOUNT_SPEED and 2 or 1
end

local function CheckMount()
  local rec = H.cdb.mount
  local tier = MountTier()
  if not tier or tier <= rec.tier then return end
  local seeding = rec.tier == 0 and (rec.base or 0) >= H.MOUNT_TIER_LEVEL[tier]
  rec.tier = tier
  Report("mount", { epic = tier == 2 or nil }, not seeding)
end

local mountArmed = false
local function OnAura(unit)
  if unit ~= "player" or mountArmed or H.cdb.mount.tier >= 2 then return end
  mountArmed = true
  C_Timer.After(1, function() mountArmed = false; GS:Call(CheckMount) end)
end

local standings
local function StandingOf(label)
  if not standings then
    standings = {}
    for i = 1, 8 do
      for _, suffix in ipairs({ "", "_FEMALE" }) do
        local text = Plain(_G["FACTION_STANDING_LABEL" .. i .. suffix], "string")
        if text then standings[text] = i end
      end
    end
  end
  return standings[label]
end

local function OnStanding(text)
  local a, b = Match(text, "FACTION_STANDING_CHANGED")
  if not a then return false end
  local standing, faction = StandingOf(a), b
  if not standing then standing, faction = StandingOf(b), a end
  if not standing or standing < H.REP_MILESTONE then return true end
  local reps = Store("reps")
  if standing <= (reps[faction] or 0) then return true end
  reps[faction] = standing
  Report("rep", { st = standing, fac = faction }, true)
  return true
end

local function WinnerFirst(global)
  local f = Plain(_G[global], "string") or ""
  local one, two = f:find("%%1%$s"), f:find("%%2%$s")
  return not (one and two and two < one)
end

local function DuelWon(winner, foe)
  if winner ~= GS:PlayerKey() or GS:IsGuildMember(foe) ~= true then return end
  local duels, now = Store("duels"), GS:Now()
  local fresh = now - (duels[foe] or 0) >= H.DUEL_EVERY
  if fresh then duels[foe] = now end
  Report("duel", { foe = foe }, fresh)
end

local function OnDuel(text)
  for _, global in ipairs({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER", "DUEL_WINNER_RETREAT" }) do
    local a, b = Match(text, global)
    if a and b then
      if not WinnerFirst(global) then a, b = b, a end
      return DuelWon(GS:NormName(a), GS:NormName(b))
    end
  end
end

local function OnSystem(text)
  text = Plain(text, "string")
  if not text or OnStanding(text) then return end
  OnDuel(text)
end

local PROFESSION_SLOTS = 6

local function IsProfession(name)
  local slots = { SafeCall(GetProfessions) }
  for i = 1, PROFESSION_SLOTS do
    local index = Plain(slots[i], "number")
    if index and Plain(SafeCall(GetProfessionInfo, index), "string") == name then return true end
  end
  return false
end

local function OnSkill(text)
  text = Plain(text, "string")
  local name, rank = Match(text or "", "SKILL_RANK_UP")
  rank = tonumber(rank)
  if rank ~= H.SKILL_TOP or not IsProfession(name) then return end
  local skills = Store("skills")
  if (skills[name] or 0) >= rank then return end
  skills[name] = rank
  Report("skill", { skill = name, rank = rank }, true)
end

local HANDLERS = {
  UNIT_AURA = OnAura,
  CHAT_MSG_SYSTEM = OnSystem,
  CHAT_MSG_COMBAT_FACTION_CHANGE = OnSystem,
  CHAT_MSG_SKILL = OnSkill,
  PLAYER_PVP_RANK_CHANGED = CheckPvpRank,
}
local NOISY = { UNIT_AURA = true, CHAT_MSG_SYSTEM = true }

for event, handle in pairs(HANDLERS) do
  H:RegisterEvent(event, function(_, ...)
    if not (H.db and H.cdb.mount) then return end
    if not NOISY[event] then Diag(event, ...) end
    handle(...)
  end)
end
