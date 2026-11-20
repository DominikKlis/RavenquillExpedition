local ADDON, ns = ...
local GCA = ns.GCA
local K = GCA.SyncKit
local C, S, Enqueue, CharState = K.C, K.S, K.Enqueue, K.CharState
local Enabled, PeerKnown, InInstance, InRange = K.Enabled, K.PeerKnown, K.InInstance, K.InRange
local b36, n36 = GCA.RQ.Wire.b36s, GCA.RQ.Wire.n36
local Token = GCA.RecipeToken

C.K_MAX_CHUNKS, C.K_SPACING, C.K_MAX_RANK, C.R_GAP = 8, 300, 999, 900
local buffers = {}

local function Header(ts, i, n, line, rank)
  return "K;" .. b36(ts) .. ";" .. i .. "/" .. n .. ";" .. b36(line) .. ";" .. b36(rank) .. ";"
end

local function PackProfession(bodies, p, budget)
  local cur, prev = { p = p, text = "" }, 0
  bodies[#bodies + 1] = cur
  for _, id in ipairs(p.ids) do
    local tok = Token(id - prev)
    if #cur.text + #tok > budget then
      cur, tok = { p = p, text = "" }, Token(id)
      bodies[#bodies + 1] = cur
    end
    cur.text, prev = cur.text .. tok, id
  end
end

function GCA:EncodeRecipeSet(set, ts)
  if set[1] == nil then return { Header(ts, 1, 1, 0, 0) } end
  local bodies = {}
  for _, p in ipairs(set) do PackProfession(bodies, p, C.MAX_MSG - #Header(ts, 9, 9, p.line, p.rank)) end
  if #bodies > C.K_MAX_CHUNKS then return nil end
  local out = {}
  for i, b in ipairs(bodies) do out[i] = Header(ts, i, #bodies, b.p.line, b.p.rank) .. b.text end
  return out
end

local function NoteOwnSet(cs, set)
  local sig = GCA.RecipeSignature(set)
  if sig == cs.kSig then return end
  if set[1] ~= nil then
    cs.kGoneTs = nil
  elseif (cs.kSig or "") ~= "" then
    cs.kGoneTs = cs.kTs
  end
  cs.kSig, cs.kTs = sig, math.max(GCA:Now(), (cs.kTs or 0) + 1)
end

local function KDue(cs, set)
  if set[1] == nil and cs.kGoneTs == nil then return false end
  return S.kOwed or cs.kTs ~= cs.kSentTs
end

local function SendOwnSet()
  S.kTimer = nil
  if not Enabled() or InInstance() or InCombatLockdown() then return end
  local set, cs = GCA:OwnRecipeSet(), CharState()
  if not set then return end
  NoteOwnSet(cs, set)
  if not KDue(cs, set) then return end
  local ts, queuedAt = cs.kTs, GetTime()
  S.kQueuedAt = queuedAt
  Enqueue("K", GCA:EncodeRecipeSet(set, ts), function()
    cs.kSentTs = ts
    if (S.lastRAt or -1e9) <= queuedAt then S.kOwed = false end
  end)
end

local function CanAnnounce() return Enabled() and PeerKnown() and not InInstance() end

function GCA:CheckOwnRecipes(answer)
  local set = self:OwnRecipeSet()
  if not (set and self.charKey) then return end
  local cs = CharState()
  NoteOwnSet(cs, set)
  if not CanAnnounce() or S.kTimer or not KDue(cs, set) then return end
  local delay = answer and (C.ANSWER_MIN + math.random() * C.ANSWER_JITTER) or C.OWN_DEBOUNCE
  S.kTimer = true
  C_Timer.After(math.max(delay, (S.kQueuedAt or -1e9) + C.K_SPACING - GetTime()), SendOwnSet)
end

local function ValidChunk(f)
  local ts, line, rank = n36(f[2], true), n36(f[4], true), n36(f[5], true)
  local i, n = (f[3] or ""):match("^(%d)/(%d)$")
  i, n = tonumber(i), tonumber(n)
  if not (InRange(ts, 0, GCA:Now() + C.FUTURE_SLACK) and InRange(n, 1, C.K_MAX_CHUNKS) and InRange(i, 1, n)) then return end
  if not (line and InRange(rank, 0, C.K_MAX_RANK)) then return end
  local ids = GCA.DecodeIDs(f[6])
  if not ids then return end
  return { ts = ts, i = i, n = n, line = line, rank = rank, ids = ids }
end

local function CompletedParts(senderKey, r)
  local id, now = senderKey .. "\0" .. r.ts, GetTime()
  for k, b in pairs(buffers) do if now - b.last > C.BUFFER_EXPIRE then buffers[k] = nil end end
  local b = buffers[id]
  if not b or b.n ~= r.n then
    b = { n = r.n, parts = {}, got = 0 }
    buffers[id] = b
  end
  b.last = now
  if not b.parts[r.i] then b.parts[r.i], b.got = r, b.got + 1 end
  if b.got < b.n then return nil end
  buffers[id] = nil
  return b.parts
end

local function MergeParts(parts)
  local profs = {}
  for _, part in ipairs(parts) do
    local p = GCA.PROF_BY_LINE[part.line]
    if p then
      local into = profs[p.key] or { rank = part.rank, ids = {} }
      profs[p.key] = into
      for _, id in ipairs(part.ids) do into.ids[#into.ids + 1] = id end
    end
  end
  return profs
end

local function OnRecipes(senderKey, f)
  local r = ValidChunk(f)
  local parts = r and CompletedParts(senderKey, r)
  if parts and GCA:StoreCrafter(senderKey, r.ts, MergeParts(parts)) then S.setsReceived = (S.setsReceived or 0) + 1 end
end

local function ListedStamps(text)
  local listed = {}
  for s in text:gmatch("[^,]+") do
    local ts = n36(s, true)
    if not ts then return nil end
    listed[ts] = true
  end
  return listed
end

local function WantsAnswer(cs, set, listed)
  if set[1] ~= nil then return not listed[cs.kTs] end
  return cs.kGoneTs ~= nil and listed[cs.kGoneTs] == true
end

local function OnRequest(_, f)
  local set, listed = GCA:OwnRecipeSet(), ListedStamps(f[2])
  if not (set and listed and GCA.charKey) then return end
  local cs = CharState()
  NoteOwnSet(cs, set)
  if not WantsAnswer(cs, set, listed) then return end
  S.kOwed, S.lastRAt = true, GetTime()
  GCA:CheckOwnRecipes(true)
end

K.HANDLERS.K = { fields = 6, fn = OnRecipes }
K.HANDLERS.R = { fields = 2, fn = OnRequest }

local function StampList(budget)
  local stamps, out, len = {}, {}, 0
  for _, c in pairs(GCA:CrafterEntries()) do
    if type(c) == "table" and tonumber(c.ts) then stamps[#stamps + 1] = tonumber(c.ts) end
  end
  table.sort(stamps, function(a, b) return a > b end)
  for _, ts in ipairs(stamps) do
    local s = b36(ts)
    if len + #s + 1 > budget then break end
    out[#out + 1], len = s, len + #s + 1
  end
  return table.concat(out, ",")
end

function GCA:RequestCrafters()
  if not Enabled() or InInstance() or not self.charKey then return end
  if not PeerKnown() then S.rWanted = true return end
  local cs = CharState()
  if cs.lastR and self:Now() - cs.lastR < C.R_GAP then return end
  cs.lastR, S.rWanted = self:Now(), nil
  Enqueue("R", { "R;" .. StampList(C.MAX_MSG - 2) })
end

function GCA:CheckCrafterRequest()
  if S.rWanted then self:RequestCrafters() end
end
