local ADDON, ns = ...
local GS = RavenquillExpedition
local G, L, A, P, UI, V = ns.G, ns.L, ns.Activities, ns.Posts, ns.UI, ns.View

local Form = {}
ns.Form = Form

local PAD, LABEL_W, FIELD_W, HEIGHT = 16, 130, 320, 316
local DAYS, STEP, DAY_MINUTES, RAID_TIME, LATE_HOUR = 7, 30, 1440, 1200, 19
local Y = { title = -14, activity = -50, filled = -86, roles = -110, note = -200, when = -236, buttons = -276 }

function Form.DefaultActivity(level)
  for _, a in ipairs(A.LIST) do
    if not a.raid and A.Fits(a, level) then return a.id end
  end
  return A.LIST[1].id
end

local function DraftOf(p, now)
  local d = { activity = p.activity, have = {}, day = 0, minutes = RAID_TIME, note = p.note or "" }
  for _, r in ipairs(P.ROLES) do d.have[r.key] = p.roles[r.key].have end
  if p.when then d.day, d.minutes = V.DaysAhead(p.when, now), math.floor((p.when - V.DayStart(p.when)) / 60) end
  return d
end

function Form.Draft(own, level, now)
  if own then return DraftOf(own, now) end
  local late = (tonumber(date("%H", now)) or 0) >= LATE_HOUR
  return { activity = Form.DefaultActivity(level), have = { tank = 0, heal = 0, dps = 0 }, day = late and 1 or 0,
    minutes = RAID_TIME, note = "" }
end

function Form.When(draft, now) return V.DayStart(now) + draft.day * 86400 + draft.minutes * 60 end

function Form.Spec(draft, now)
  local a = A.Get(draft.activity)
  local need, roles = A.Needs(a), {}
  for _, r in ipairs(P.ROLES) do
    roles[r.key] = { need = need[r.key], have = math.min(draft.have[r.key] or 0, need[r.key]) }
  end
  local when = a.raid and Form.When(draft, now) or nil
  if when and when <= now then return nil, L.PAST end
  return { activity = a.id, roles = roles, when = when, note = GS.Wire.Clean(draft.note, ns.Sync.C.NOTE_MAX) }
end

local function ActivityLabel(a, level)
  local text = a.raid and A.Name(a) or ("%s (%d-%d)"):format(A.Name(a), a.min, a.max)
  if A.Fits(a, level) then return "|cff80ff80" .. text .. "|r" end
  return text
end

local function Dropdown(parent, width, gen, fallback)
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if not (ok and dd and type(dd.SetupMenu) == "function") then dd = UI.Button(parent, width, "", fallback) end
  dd:SetSize(width, 24)
  dd.menu = gen
  if type(dd.SetupMenu) == "function" then dd:SetupMenu(gen) end
  return dd
end

local function ShowChoice(dd, text)
  if type(dd.GenerateMenu) == "function" then pcall(dd.GenerateMenu, dd) end
  if type(dd.OverrideText) == "function" then dd:OverrideText(text) else dd:SetText(text) end
end

local function Label(form, y, text)
  local fs = UI.Text(form, "GameFontNormal")
  fs:SetPoint("TOPLEFT", PAD, y)
  fs:SetWidth(LABEL_W)
  fs:SetText(text)
  return fs
end

local function Stepper(form, x, y, onStep)
  local s = {}
  s.minus = UI.Button(form, 26, "-", function() onStep(-1) end)
  s.minus:SetPoint("TOPLEFT", x, y + 4)
  s.value = UI.Text(form, "GameFontHighlight", "CENTER")
  s.value:SetPoint("LEFT", s.minus, "RIGHT", 4, 0)
  s.value:SetWidth(56)
  s.plus = UI.Button(form, 26, "+", function() onStep(1) end)
  s.plus:SetPoint("LEFT", s.value, "RIGHT", 4, 0)
  return s
end

function Form.SetActivity(form, id)
  form.draft.activity = id
  Form.Render(form)
end

function Form.SetDay(form, day)
  form.draft.day = day
  Form.Render(form)
end

function Form.Bump(form, role, dir)
  local need = A.Needs(A.Get(form.draft.activity))[role]
  form.draft.have[role] = math.max(0, math.min(need, (form.draft.have[role] or 0) + dir))
  Form.Render(form)
end

function Form.Shift(form, dir)
  form.draft.minutes = (form.draft.minutes + dir * STEP) % DAY_MINUTES
  Form.Render(form)
end

local function ActivityMenu(form)
  return function(_, root)
    for _, section in ipairs({ { L.DUNGEONS, false }, { L.RAIDS, true } }) do
      root:CreateTitle(section[1])
      for _, a in ipairs(A.LIST) do
        if (a.raid or false) == section[2] then
          root:CreateRadio(ActivityLabel(a, G:PlayerLevel()), function(id) return form.draft.activity == id end,
            function(id) Form.SetActivity(form, id) end, a.id)
        end
      end
    end
  end
end

local function DayMenu(form)
  return function(_, root)
    local now = GS:Now()
    for day = 0, DAYS - 1 do
      root:CreateRadio(V.DayName(now + day * 86400, now), function(d) return form.draft.day == d end,
        function(d) Form.SetDay(form, d) end, day)
    end
  end
end

local function Cycle(form, field, list)
  local at = 1
  for i, v in ipairs(list) do if v == form.draft[field] then at = i end end
  form.draft[field] = list[at % #list + 1]
  Form.Render(form)
end

local function ActivityIds()
  local out = {}
  for i, a in ipairs(A.LIST) do out[i] = a.id end
  return out
end

local function BuildActivity(form)
  Label(form, Y.activity, L.FORM_ACTIVITY)
  form.activity = Dropdown(form, FIELD_W, ActivityMenu(form), function() Cycle(form, "activity", ActivityIds()) end)
  form.activity:SetPoint("TOPLEFT", PAD + LABEL_W, Y.activity + 5)
end

local function BuildRoles(form)
  Label(form, Y.filled, L.FORM_FILLED)
  form.roles = {}
  for i, r in ipairs(P.ROLES) do
    local y = Y.roles - (i - 1) * 28
    local s = Stepper(form, PAD + LABEL_W, y, function(dir) Form.Bump(form, r.key, dir) end)
    s.label = UI.Text(form, "GameFontHighlight")
    s.label:SetPoint("TOPLEFT", PAD + 12, y)
    s.label:SetText(V.RoleName(r.key))
    form.roles[r.key] = s
  end
end

local function BuildNote(form)
  Label(form, Y.note, L.FORM_NOTE)
  local eb = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
  eb:SetSize(FIELD_W, 20)
  eb:SetPoint("TOPLEFT", PAD + LABEL_W + 6, Y.note + 3)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(ns.Sync.C.NOTE_MAX)
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  eb:SetScript("OnEnterPressed", eb.ClearFocus)
  form.note = eb
end

local function BuildWhen(form)
  form.whenLabel = Label(form, Y.when, L.FORM_WHEN)
  form.day = Dropdown(form, 140, DayMenu(form), function() Cycle(form, "day", { 0, 1, 2, 3, 4, 5, 6 }) end)
  form.day:SetPoint("TOPLEFT", PAD + LABEL_W, Y.when + 5)
  form.time = Stepper(form, PAD + LABEL_W + 152, Y.when, function(dir) Form.Shift(form, dir) end)
end

local function BuildButtons(form)
  form.submit = UI.Button(form, 130, L.POST, function() Form.Submit(form) end)
  form.submit:SetPoint("TOPLEFT", PAD + LABEL_W, Y.buttons)
  form.cancel = UI.Button(form, 110, L.CANCEL, function() Form.Close(form) end)
  form.cancel:SetPoint("LEFT", form.submit, "RIGHT", 8, 0)
  form.error = UI.Text(form, "GameFontHighlightSmall")
  form.error:SetPoint("LEFT", form.cancel, "RIGHT", 12, 0)
  form.error:SetTextColor(1, 0.4, 0.3)
end

function Form.Build(page)
  local form = UI.Card(page)
  form:SetPoint("TOPLEFT", 0, 0)
  form:SetPoint("RIGHT", page, "RIGHT", -14, 0)
  form:SetHeight(HEIGHT)
  form.title = UI.Text(form, "GameFontNormalLarge")
  form.title:SetPoint("TOPLEFT", PAD, Y.title)
  BuildActivity(form)
  BuildRoles(form)
  BuildNote(form)
  BuildWhen(form)
  BuildButtons(form)
  form:Hide()
  return form
end

local function RenderStepper(s, have, need)
  s.value:SetText(have .. "/" .. need)
  s.minus:SetEnabled(have > 0)
  s.plus:SetEnabled(have < need)
end

local function RenderWhen(form, raid)
  for _, f in ipairs({ form.whenLabel, form.day, form.time.minus, form.time.value, form.time.plus }) do f:SetShown(raid) end
  if not raid then return end
  local now, m = GS:Now(), form.draft.minutes
  ShowChoice(form.day, V.DayName(now + form.draft.day * 86400, now))
  form.time.value:SetText(("%02d:%02d"):format(math.floor(m / 60), m % 60))
end

function Form.Render(form)
  local a = A.Get(form.draft.activity)
  local need = A.Needs(a)
  ShowChoice(form.activity, ActivityLabel(a, G:PlayerLevel()))
  for _, r in ipairs(P.ROLES) do
    form.draft.have[r.key] = math.min(form.draft.have[r.key] or 0, need[r.key])
    RenderStepper(form.roles[r.key], form.draft.have[r.key], need[r.key])
  end
  RenderWhen(form, a.raid or false)
  form.submit:SetText(G:OwnPost() and L.UPDATE or L.POST)
end

function Form.Open(form, own)
  form.draft = Form.Draft(own, G:PlayerLevel(), GS:Now())
  form.title:SetText(own and L.FORM_EDIT or L.FORM_NEW)
  form.note:SetText(form.draft.note)
  form.error:SetText("")
  form:Show()
  Form.Render(form)
  G:RenderPage()
end

function Form.Close(form)
  form:Hide()
  G:RenderPage()
end

function Form.Submit(form)
  form.draft.note = form.note:GetText() or ""
  local spec, problem = Form.Spec(form.draft, GS:Now())
  if not spec then return form.error:SetText(problem) end
  G:Post(spec)
  Form.Close(form)
end
