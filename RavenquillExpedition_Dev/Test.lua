local ADDON, ns = ...
local RQ = RavenquillExpedition
local Dev = ns.Dev

Dev.tests, Dev.testOrder = {}, {}
Dev.RUNS_MAX = 20

function Dev:Register(name, fn, timeout, opts)
  if not self.tests[name] then self.testOrder[#self.testOrder + 1] = name end
  self.tests[name] = { fn = fn, timeout = timeout or 20, manual = opts and opts.manual or false }
end

local function Names(sel)
  if sel == nil or sel == "all" then
    local out = {}
    for _, name in ipairs(Dev.testOrder) do if not Dev.tests[name].manual then out[#out + 1] = name end end
    return out
  end
  if type(sel) == "string" then sel = { sel } end
  local out = {}
  for _, want in ipairs(sel) do
    for _, name in ipairs(Dev.testOrder) do
      if name == want or (name:sub(1, #want + 1) == want .. "." and not Dev.tests[name].manual) then out[#out + 1] = name end
    end
  end
  return out
end

function Dev:Run(sel, runId, onFinished)
  local db = self.db
  if self.running then Dev.Add("test", "busy: a run is in progress") return end
  local names = Names(sel)
  local run = { id = tostring(runId or ("manual-" .. time())), started = time(), results = {} }
  db.runs[#db.runs + 1] = run
  while #db.runs > self.RUNS_MAX do table.remove(db.runs, 1) end
  self.running = run
  Dev.Add("test", "run start " .. run.id, #names .. " tests")
  local i = 0
  local function Next()
    i = i + 1
    local name = names[i]
    if not name then
      run.finished = time()
      local pass, total = 0, 0
      for _, r in ipairs(run.results) do total = total + 1; if r.status:sub(1, 4) == "pass" then pass = pass + 1 end end
      run.summary = ("%d/%d passed"):format(pass, total)
      self.running = nil
      Dev.Add("test", "run done " .. run.id, run.summary)
      if onFinished then RQ:Call(onFinished, run) end
      return
    end
    local test = self.tests[name]
    local res = { name = name, status = "running", checks = {}, notes = {}, started = GetTime() }
    run.results[#run.results + 1] = res
    local finished = false
    local t = {}
    local function Finish(status)
      if finished then return end
      finished = true
      if status == "done" then
        status = "pass"
        for _, c in ipairs(res.checks) do if not c[1] then status = "fail" end end
        if not res.checks[1] then status = "pass (no checks)" end
      end
      res.status, res.seconds = status, math.floor((GetTime() - res.started) * 10 + 0.5) / 10
      Dev.Add("test", name .. ": " .. status)
      C_Timer.After(0.5, Next)
    end
    t.ok = function(_, cond, label) res.checks[#res.checks + 1] = { cond and true or false, tostring(label) } end
    t.note = function(_, text) res.notes[#res.notes + 1] = tostring(text) end
    t.done = function() Finish("done") end
    t.after = function(_, sec, fn)
      C_Timer.After(sec, function()
        if finished then return end
        local ok, err = pcall(fn)
        if not ok then t:note("error: " .. tostring(err)); Finish("error") end
      end)
    end
    C_Timer.After(test.timeout, function() if not finished then Finish("timeout") end end)
    local ok, err = pcall(test.fn, t)
    if not ok then t:note("error: " .. tostring(err)); Finish("error") end
  end
  Next()
  return run
end

function Dev:RunAll() return self:Run("all") end

function Dev:OnLoginTests()
  local inbox = rawget(_G, "RQDevInbox")
  if type(inbox) ~= "table" or inbox.id == nil then return end
  local id = tostring(inbox.id)
  if id == self.db.lastId then return end
  self.db.lastId = id
  Dev.Add("inbox", "run " .. id)
  C_Timer.After(tonumber(inbox.delay) or 5, function()
    self:Run(inbox.run or "all", id, function(run)
      RQ.Print("Dev", ("|cffffff00inbox %s: %s. Type /reload to save the results.|r"):format(id, run.summary or "?"))
    end)
  end)
end
