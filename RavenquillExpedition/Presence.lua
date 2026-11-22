local ADDON, ns = ...
local GS = ns.GS
local C = GS.CommConst

local heard, onlineSince = {}, {}
local helloAt
local answer = "idle"

local channel = ns.ModuleProto.NewChannel({ name = "core" }, { tag = "V" })
channel:Define("v", { fields = { { "ver", "text", 24 } } })
channel:Define("p", { fields = {} })

local SendReply
local function ReplyAfter(delay)
  answer = "due"
  C_Timer.After(delay, function() GS:Call(SendReply) end)
end

SendReply = function()
  if answer ~= "due" then return end
  answer = "sending"
  channel:Send("p", {}, { onResult = function(status)
    if status == "dropped" then ReplyAfter(C.VERSION_RETRY) else answer = "idle" end
  end })
end

channel:On("v", function(sender, msg)
  GS:NotePeerVersion(sender, msg.ver)
  if answer == "idle" then ReplyAfter(math.random() * C.REPLY_JITTER) end
end)

local function Announce()
  channel:Send("v", { ver = GS.version }, { onResult = function(status)
    if status == "dropped" then return C_Timer.After(C.VERSION_RETRY, function() GS:Call(Announce) end) end
    answer = "idle"
    if status == "delivered" then helloAt = GetTime() end
  end })
end

function GS:OnLoginPresence()
  if not GS.IsRelease(self.version) then return end
  answer = "sending"
  C_Timer.After(C.VERSION_DELAY + math.random() * C.VERSION_JITTER, function()
    GS:Call(GS.CheckPeerVersions, GS)
    GS:Call(Announce)
  end)
end

function ns.NoteHeard(key) heard[key] = true end

function ns.ForgetPresence() heard, onlineSince, helloAt = {}, {}, nil end

function ns.NoteOnline(roster)
  local now = GetTime()
  for key, e in pairs(roster) do onlineSince[key] = e.online and (onlineSince[key] or now) or nil end
end

function GS:Presence(key)
  if not key then return "unknown" end
  if heard[key] or self:IsMe(key) then return "confirmed" end
  local since = onlineSince[key]
  if not (helloAt and since) then return "unknown" end
  if GetTime() - math.max(helloAt, since) < C.REPLY_WINDOW or self:IsPeer(key) then return "pending" end
  return "absent"
end
