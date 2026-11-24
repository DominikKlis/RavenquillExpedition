local ADDON, ns = ...
local GS = RavenquillExpedition
local H = ns.H

local foldLines = setmetatable({}, { __mode = "k" })
local heldLines = setmetatable({}, { __mode = "k" })

local function Listed(list, x)
  for _, y in ipairs(list or {}) do if y == x then return true end end
  return false
end

function H.Involves(line, who) return line.who == who or Listed(line.with, who) end

function H.Firsts(members, out)
  out = out or {}
  for _, m in ipairs(members) do
    if m.first and not Listed(out, m.who) then out[#out + 1] = m.who end
  end
  return out
end

function H:Shown(e)
  local kind = self.KINDS[e.k]
  return not (kind and kind.hidden and kind.hidden(e))
end

local function Among(members, who)
  for _, m in ipairs(members) do if m.who == who then return true end end
  return false
end

local function AnyUnseen(members)
  for _, m in ipairs(members) do if m.unseen then return true end end
  return false
end

local function FoldRule(self, e)
  local rule = (self.KINDS[e.k] or {}).fold
  if rule and (not rule.of or rule.of(e)) then return rule end
end

local function Holder(self, rule, e, events)
  local holds = self.KINDS[rule.into].holds
  if not holds then return nil end
  for _, o in ipairs(events) do
    if o.k == rule.into and holds(self, o, e) then return o end
  end
end

local function Join(self, folds, rule, e)
  for _, f in ipairs(folds) do
    if f.rule == rule and rule.joins(self, f, e) then
      f[#f + 1] = e
      return
    end
  end
  folds[#folds + 1] = { rule = rule, e }
end

local function Gather(self, events, at, held, by)
  local folds = {}
  for _, e in ipairs(events) do
    local rule = FoldRule(self, e)
    local holder = rule and Holder(self, rule, e, events)
    if holder then
      at[e], held[holder], by[e] = false, H.Firsts({ e }, held[holder]), holder
    elseif rule then
      Join(self, folds, rule, e)
    end
  end
  return folds
end

local function FoldLine(f)
  local first, rule = f[1], f.rule
  local line = foldLines[first] or {}
  foldLines[first] = line
  line.k, line.t, line.id, line.who, line.cls, line.lvl = rule.into, first.t, first.id, first.who, first.cls, first.lvl
  for _, key in ipairs(rule.keep) do line[key] = first[key] end
  line.unseen = AnyUnseen(f) and not Among(f, GS:PlayerKey()) or nil
  rule.fill(line, f)
  return line
end

local function Place(f, at, by)
  if #f < f.rule.min then return end
  at[f[1]] = FoldLine(f)
  for i = 2, #f do at[f[i]], by[f[i]] = false, f[1] end
end

local function Held(e, firsts)
  if not (firsts and firsts[1]) then return e end
  local line = heldLines[e] or setmetatable({}, { __index = e })
  heldLines[e], line.firsts = line, firsts
  return line
end

local function Yields(self, line, lines)
  local to = self.KINDS[line.k].yieldsTo
  if not to then return false end
  for _, o in ipairs(lines) do
    if to[o.k] and H.SameDungeon(o.inst, line.inst) and H.Involves(o, line.who) then return true end
  end
  return false
end

local function Lines(self)
  local events, at, held, by = self:Log(), {}, {}, {}
  for _, f in ipairs(Gather(self, events, at, held, by)) do Place(f, at, by) end
  local lines, anchors = {}, {}
  for _, e in ipairs(events) do
    local line = at[e]
    if line == nil then line = self:Shown(e) and Held(e, held[e]) end
    if line then lines[#lines + 1], anchors[#anchors + 1] = line, e end
  end
  local out, of = {}, {}
  for i, line in ipairs(lines) do
    if not Yields(self, line, lines) then out[#out + 1], of[anchors[i]] = line, line end
  end
  return out, of, by
end

function H:ShownLog() return (Lines(self)) end

function H:LineOf(e)
  local _, of, by = Lines(self)
  return of[by[e] or e]
end

function H:Folding(e) return FoldRule(self, e) ~= nil or self.KINDS[e.k].holds ~= nil end
