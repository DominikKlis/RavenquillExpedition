local o = { last = 80 }
do
  local i = 1
  while arg[i] do
    local a = arg[i]
    if a == "--sv" or a == "--bugs" or a == "--framexml" or a == "--cat" or a == "--run" then o[a:sub(3)] = arg[i + 1]; i = i + 1
    elseif a == "--last" then o.last = tonumber(arg[i + 1]); i = i + 1
    elseif a == "--runs" then o.runs = true
    elseif a == "--session" then o.session = true
    end
    i = i + 1
  end
end

local function loadSV(path, name)
  if not path then return nil end
  local env = {}
  local f = loadfile(path, "t", env)
  if not f then return nil, "cannot read " .. path end
  local ok, err = pcall(f)
  if not ok then return nil, "parse error (the game may be writing it, retry): " .. tostring(err) end
  return env[name]
end

local db, err = loadSV(o.sv, "RavenquillExpeditionDevDB")
if not db then
  print("No dev log: " .. tostring(err or ("RavenquillExpeditionDevDB missing in " .. tostring(o.sv))))
  print("(Is RavenquillExpedition_Dev enabled for this character? SavedVariables are written on /reload and logout.)")
else
  local s = db.sessions and db.sessions[#db.sessions]
  if s then
    local mods = {}
    for k, v in pairs(s.modules or {}) do mods[#mods + 1] = k .. " " .. tostring(v) end
    table.sort(mods)
    print(("== session %s  client %s (interface %s)  core %s  %s @ %s"):format(os.date("%Y-%m-%d %H:%M:%S", s.started),
      tostring(s.build), tostring(s.interface), tostring(s.core), tostring(s.char), tostring(s.guild)))
    print("   modules: " .. table.concat(mods, ", "))
  end
  local log = db.log or { e = {}, n = 0, max = 1, head = 1 }
  local entries = {}
  local start = log.n < log.max and 1 or log.head
  for i = 0, log.n - 1 do entries[#entries + 1] = log.e[(start - 1 + i) % log.max + 1] end
  if o.session and s then
    local keep = {}
    for _, e in ipairs(entries) do if e[1] >= s.started - 5 then keep[#keep + 1] = e end end
    entries = keep
  end
  if o.cat then
    local keep = {}
    for _, e in ipairs(entries) do if tostring(e[3]):sub(1, #o.cat) == o.cat then keep[#keep + 1] = e end end
    entries = keep
  end
  if not o.runs and not o.run then
    print(("== log: %d entries%s, showing the last %d (logging %s)"):format(#entries, o.cat and (" in " .. o.cat) or "",
      math.min(o.last, #entries), db.on and "on" or "off"))
    for i = math.max(1, #entries - o.last + 1), #entries do
      local e = entries[i]
      print(("%s %8.1f %-12s %s%s"):format(os.date("%H:%M:%S", e[1]), e[2] or 0, e[3], e[4] or "", e[5] and ("  | " .. e[5]) or ""))
    end
  end
  local runs = db.runs or {}
  local function printRun(run)
    print(("== test run %s  %s  %s"):format(run.id, os.date("%H:%M:%S", run.started), run.summary or "(not finished)"))
    for _, r in ipairs(run.results or {}) do
      print(("  %-8s %-16s %ss"):format(r.status, r.name, tostring(r.seconds or "?")))
      for _, c in ipairs(r.checks or {}) do print(("      %s %s"):format(c[1] and "ok  " or "FAIL", c[2])) end
      for _, n in ipairs(r.notes or {}) do print("      note: " .. n) end
    end
  end
  if o.run then
    local found
    for _, run in ipairs(runs) do if run.id == o.run then found = run end end
    if found then printRun(found) else print("== test run " .. o.run .. ": not in the file yet") end
  elseif o.runs then
    for _, run in ipairs(runs) do printRun(run) end
  elseif runs[#runs] then
    printRun(runs[#runs])
  end
end

if o.bugs then
  local bg = loadSV(o.bugs, "BugGrabberDB")
  local n = 0
  for _, e in ipairs(bg and bg.errors or {}) do
    local text = tostring(e.message) .. "\n" .. tostring(e.stack)
    if text:find("Ravenquill", 1, true) then
      n = n + 1
      if n == 1 then print("== BugGrabber: errors mentioning Ravenquill (newest last)") end
      print(("-- %s  session %s  x%s"):format(tostring(e.time), tostring(e.session), tostring(e.counter)))
      print("   " .. tostring(e.message))
      for line in tostring(e.stack or ""):gmatch("[^\n]+") do print("   " .. line) end
      if e.locals then print("   locals: " .. tostring(e.locals):sub(1, 400):gsub("\n", " | ")) end
    end
  end
  if n == 0 then print("== BugGrabber: no errors mentioning Ravenquill") end
end

if o.framexml then
  local f = io.open(o.framexml, "rb")
  if f then
    local hits = {}
    for line in f:lines() do if line:find("Ravenquill", 1, true) then hits[#hits + 1] = line end end
    f:close()
    print(("== FrameXML.log: %d lines mentioning Ravenquill"):format(#hits))
    for i = math.max(1, #hits - 20), #hits do print("   " .. hits[i]) end
  end
end
