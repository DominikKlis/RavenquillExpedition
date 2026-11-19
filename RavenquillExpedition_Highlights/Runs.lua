local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H
local SafeCall, Plain = GS.SafeCall, GS.Plain

H.RUN_GRACE = 600

local function CurrentInstance()
  local inst, itype = SafeCall(GetInstanceInfo)
  return Plain(inst, "string"), Plain(itype, "string")
end

local function FinishRun(self)
  local run = self.cdb.run
  self.cdb.run = nil
  if not run or (run.news or 0) == 0 then return end
  self.cdb.dungeons = self.cdb.dungeons or {}
  local firstRun = run.news == run.kills and not self.cdb.dungeons[run.inst]
  self.cdb.dungeons[run.inst] = true
  local e = ns.Own("run", { inst = run.inst, boss = run.boss, n = run.kills, nf = run.news, first = firstRun or nil })
  if e then self:Add(e, "self") end
end

function H:NoteDungeonKill(inst, boss, new)
  if not inst then return end
  local run = self.cdb.run
  if run and run.inst ~= inst then FinishRun(self) end
  run = self.cdb.run or { inst = inst, kills = 0, news = 0 }
  run.kills, run.boss, run.left = run.kills + 1, boss, nil
  if new then run.news = run.news + 1 end
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
