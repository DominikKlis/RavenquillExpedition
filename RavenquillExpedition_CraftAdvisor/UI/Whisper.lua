local ADDON, ns = ...
local GCA, L = ns.GCA, ns.L
local UI = GCA.UI
local P = UI.P
local SafeCall, LGet, SlotName, FirstName = P.SafeCall, P.LGet, P.SlotName, P.FirstName

local function CrafterNoun(prof)
  local v = LGet and LGet("CRAFTER_" .. tostring(prof):upper())
  if v then return v end
  local p = GCA.PROF_BY_KEY[prof] or GCA.PROF_BY_KEY.Leatherworking
  return p.crafter
end

function UI.DefaultTemplate(kind)
  return kind == "enchant" and L.WHISPER_ENCHANT or L.WHISPER_CRAFT
end

function UI.Template(kind)
  local s = GCA.db and GCA.db.settings
  local t = s and (kind == "enchant" and s.whisperEnchant or s.whisperCraft)
  if type(t) == "string" and t:find("%S") then return t end
  return UI.DefaultTemplate(kind)
end

function UI.FillTemplate(t, vals)
  if vals.name == nil or vals.name == "" then t = t:gsub("%s*{name}", "") end
  return (t:gsub("{(%a+)}", function(k)
    local v = vals[k:lower()]
    if v ~= nil then return tostring(v) end
  end))
end

UI.WHISPER_MAX = 255
function UI.Utf8Cut(s, max)
  if #s <= max then return s end
  local cut = s:sub(1, max)
  local j = #cut
  while j > 0 do
    local c = cut:byte(j)
    if c < 0x80 or c >= 0xC0 then break end
    j = j - 1
  end
  if j > 0 then
    local c = cut:byte(j)
    local len = (c >= 0xF0 and 4) or (c >= 0xE0 and 3) or (c >= 0xC0 and 2) or 1
    if j + len - 1 > #cut then cut = cut:sub(1, j - 1) end
  end
  return (cut:gsub("|+$", ""))
end

function UI.OfferText(prof, d, who)
  local kind = d.kind == "enchant" and "enchant" or "craft"
  local item
  if kind == "enchant" then item = d.info.name or d.enchant.name else item = d.info.link or d.info.name end
  local vals = { item = item, slot = SlotName(d.slot), name = FirstName(who), crafter = CrafterNoun(prof) }
  local msg = UI.FillTemplate(UI.Template(kind), vals)
  if #msg > UI.WHISPER_MAX and d.info.name and item ~= d.info.name then
    vals.item = d.info.name
    msg = UI.FillTemplate(UI.Template(kind), vals)
  end
  if #msg > UI.WHISPER_MAX then
    msg = UI.Utf8Cut(msg, UI.WHISPER_MAX)
    if not UI.warnedLong then
      UI.warnedLong = true
      GCA:Print(L.WHISPER_TOO_LONG)
    end
  end
  return msg
end

function UI.CanOffer(cur, d)
  if not (cur and d) or cur.isSelf or cur.browse or not d.known then return false end
  if not cur.online then return false end
  return true
end

local function WearableText(d)
  local togo = d.levelsToGo or 0
  if togo == 1 then return string.format(L.WEARABLE_AT_1, d.wearAt or 0) end
  return string.format(L.WEARABLE_AT, d.wearAt or 0, togo)
end
UI.WearableText = WearableText

local CFU = ChatFrameUtil

local function ActiveEditBox()
  local eb = CFU and CFU.GetActiveWindow and SafeCall(CFU.GetActiveWindow)
  if not eb and ChatEdit_GetActiveWindow then eb = SafeCall(ChatEdit_GetActiveWindow) end
  return eb
end

local function OpenChatBox()
  local eb = CFU.OpenChat("", DEFAULT_CHAT_FRAME)
  if not eb and type(CFU.ChooseBoxForSend) == "function" then eb = CFU.ChooseBoxForSend(DEFAULT_CHAT_FRAME) end
  if not eb then eb = ActiveEditBox() end
  if eb and eb.SetChatType and eb.SetTellTarget and eb.SetText then return eb end
end

local function WhispersTo(eb, name)
  local kind = eb.GetChatType and eb:GetChatType()
  local target = eb.GetTellTarget and eb:GetTellTarget()
  return not (GCA.IsSecret(kind) or GCA.IsSecret(target)) and kind == "WHISPER" and target == name
end

local function FillWhisper(name, msg)
  local eb = OpenChatBox()
  if not eb then return false end
  eb:SetChatType("WHISPER")
  eb:SetTellTarget(name)
  if eb.UpdateHeader then eb:UpdateHeader() end
  if not WhispersTo(eb, name) then
    eb:SetText("")
    return false
  end
  eb:SetText(msg)
  if eb.SetFocus then eb:SetFocus() end
  return true
end

local function NativeWhisper(name, msg)
  if not (CFU and type(CFU.OpenChat) == "function") then return false end
  local ok, done = pcall(FillWhisper, name, msg)
  return ok and done == true
end
UI.NativeWhisper = NativeWhisper

local function OpenWhisper(name, msg)
  if NativeWhisper(name, msg) then return end
  local open = (CFU and CFU.OpenChat) or ChatFrame_OpenChat
  if open and pcall(open, "/w " .. name .. " " .. msg) then
    C_Timer.After(0.05, function()
      local eb = ActiveEditBox()
      local text = eb and eb.GetText and SafeCall(eb.GetText, eb)
      if eb and text and text:find(msg, 1, true) then return end
      local tell = (CFU and CFU.SendTell) or ChatFrame_SendTell
      if tell then pcall(tell, name) end
      C_Timer.After(0.05, function()
        local eb2 = ActiveEditBox()
        if eb2 and eb2.SetText then
          eb2:SetText(msg)
        elseif CFU and CFU.InsertLink then
          pcall(CFU.InsertLink, msg)
        else
          GCA:Print(string.format(L.WHISPER_TEXT, msg))
        end
      end)
    end)
    return
  end
  GCA:Print(string.format(L.WHISPER_TEXT, msg))
end
UI.OpenWhisper = OpenWhisper

local function SendWhisper(name, msg, sentFmt)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if send and pcall(send, msg, "WHISPER", nil, name) then
    GCA:Print(string.format(sentFmt or L.WHISPER_SENT, name))
  else
    OpenWhisper(name, msg)
  end
end

P.OpenWhisper = OpenWhisper
P.SendWhisper = SendWhisper
