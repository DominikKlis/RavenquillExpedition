local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local SafeCall, Plain = GS.SafeCall, GS.Plain

H.RUN_GRACE = 600
H.RUN_FOLD = 2 * H.RUN_GRACE
H.KILL_SLACK = 60
H.RUN_COUNT_MAX = 99

local function CurrentInstance()
  local inst, itype = SafeCall(GetInstanceInfo)
  return Plain(inst, "string"), Plain(itype, "string")
end

local function Guildmates(set)
  local all, out, used = {}, {}, 0
  for key in pairs(set or {}) do all[#all + 1] = key end
  table.sort(all)
  for _, key in ipairs(all) do
    used = used + #key + 1
    if used <= H.GROUP_NAMES_MAX then out[#out + 1] = key end
  end
  return out
end

local function Dungeons(self)
  if type(self.cdb.dungeons) ~= "table" then self.cdb.dungeons = {} end
  return self.cdb.dungeons
end

local function FirstRun(self, run)
  local done = Dungeons(self)
  local first = not done[run.inst] and (run.news or 0) > 0
  done[run.inst] = true
  if not first then return nil end
  local n, nf = math.min(run.kills, H.RUN_COUNT_MAX), math.min(run.news, H.RUN_COUNT_MAX)
  return ns.Own("run", { inst = run.inst, boss = run.boss, n = n, nf = nf, first = true }, run.at)
end

local function FinishRun(self)
  local run = self.cdb.run
  self.cdb.run = nil
  if not run then return end
  local first, with = FirstRun(self, run), Guildmates(run.with)
  local group = with[1] and ns.Own("group", { inst = run.inst, with = with, grp = true }, run.at)
  if group then self:Add(group, "self", { group = true, rank = (GS:ElectionRank(with)) }) end
  if first then self:Add(first, "self") end
end

local function AddGuildmates(run)
  run.with = type(run.with) == "table" and run.with or {}
  for _, key in ipairs(GS:GroupGuildies()) do run.with[key] = true end
end

local function AddKill(run, boss, new)
  run.kills, run.news, run.boss = (run.kills or 0) + 1, (run.news or 0) + (new and 1 or 0), boss
  run.at, run.left = GS:Now(), nil
end

function H:NoteDungeonKill(inst, boss, new)
  if not inst then return end
  local run = self.cdb.run
  if run and run.inst ~= inst then FinishRun(self) end
  run = self.cdb.run or { inst = inst }
  AddGuildmates(run)
  AddKill(run, boss, new)
  self.cdb.run = run
end

function H:CheckRun()
  local run = self.cdb and self.cdb.run
  if run and run.left and GS:Now() - run.left >= self.RUN_GRACE then FinishRun(self) end
end

local function ReturnedTo(self, run)
  local inst = CurrentInstance()
  if inst == run.inst then run.left = nil else FinishRun(self) end
end

function H:OnRunZone(inside)
  local run = self.cdb.run
  if not run then return end
  if inside then return ReturnedTo(self, run) end
  run.left = run.left or GS:Now()
  self:CheckRun()
  if self.cdb.run then C_Timer.After(self.RUN_GRACE + 1, function() GS:Call(H.CheckRun, H) end) end
end
