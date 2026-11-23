local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local SafeCall, Plain = GS.SafeCall, GS.Plain

H.RUN_GRACE = 600

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

local function FinishRun(self)
  local run = self.cdb.run
  self.cdb.run = nil
  local with = run and Guildmates(run.with)
  if not (with and with[1]) then return end
  local e = ns.Own("group", { inst = run.inst, with = with, grp = true }, run.at)
  if e then self:Add(e, "self", { group = true, rank = (GS:ElectionRank(with)) }) end
end

function H:NoteDungeonKill(inst)
  if not inst then return end
  local run = self.cdb.run
  if run and run.inst ~= inst then FinishRun(self) end
  run = self.cdb.run or { inst = inst }
  run.with = type(run.with) == "table" and run.with or {}
  for _, key in ipairs(GS:GroupGuildies()) do run.with[key] = true end
  run.at, run.left = GS:Now(), nil
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
