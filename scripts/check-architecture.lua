local ROOT = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
local BASELINE = ROOT .. "scripts/arch-baseline.lua"

local opts = { update = false }
do
  local i = 1
  while arg[i] do
    local a = arg[i]
    if a == "--update" then opts.update = true
    elseif a == "--checks" then opts.checks = tonumber(arg[i + 1]); i = i + 1
    elseif a == "--skips" then opts.skips = tonumber(arg[i + 1]); i = i + 1
    elseif a == "--skipnames" then opts.skipnames = arg[i + 1]; i = i + 1
    elseif a == "--luacheck" then opts.luacheck = tonumber(arg[i + 1]); i = i + 1
    end
    i = i + 1
  end
end

local function shell(cmd) local p = io.popen(cmd); local o = p:read("*a"); p:close(); return o end
local function readFile(path) local f = io.open(path, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local function lines(s) local out = {} for l in (s .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = (l:gsub("\r$", "")) end return out end

local all = {}
for p in shell('git -C "' .. ROOT .. '" ls-files --cached --others --exclude-standard'):gmatch("[^\r\n]+") do all[#all + 1] = p end
table.sort(all)

local function isShippedLua(p)
  return p:match("^RavenquillExpedition[%w_]*/") and p:match("%.lua$") and not p:match("/dev/") and not p:match("/libs/")
    and not p:match("/Data/") and not p:match("^RavenquillExpedition_Dev/")
end
local function isCore(p) return p:match("^RavenquillExpedition/") ~= nil end
local shipped, devFiles, scriptFiles = {}, {}, {}
for _, p in ipairs(all) do
  if isShippedLua(p) then shipped[#shipped + 1] = p end
  if p:match("^RavenquillExpedition[%w_]*/dev/") and p:match("%.lua$") and not p:match("/fixtures/") then devFiles[#devFiles + 1] = p end
  if p:match("^scripts/") and not p:match("check%-architecture") and not p:match("arch%-baseline") then scriptFiles[#scriptFiles + 1] = p end
end

local cache = {}
local function fileLines(p)
  if not cache[p] then cache[p] = lines(readFile(ROOT .. p) or "") end
  return cache[p]
end
local function code(l) return (l:gsub("%-%-.*$", "")) end

local function countCode(files, patterns, filter, occurrences)
  local n, where = 0, {}
  for _, p in ipairs(files) do
    if not filter or filter(p) then
      for i, l in ipairs(fileLines(p)) do
        local c = code(l)
        for _, pat in ipairs(patterns) do
          local hits = 0
          if occurrences then for _ in c:gmatch(pat) do hits = hits + 1 end elseif c:find(pat) then hits = 1 end
          if hits > 0 then n = n + hits; where[#where + 1] = p .. ":" .. i; if not occurrences then break end end
        end
      end
    end
  end
  return n, where
end

local LUAC
for _, c in ipairs({ os.getenv("LUAC") or "", "luac", "luac5.4", "luac54" }) do
  if c ~= "" and shell(c .. " -v 2>&1"):match("Lua") then LUAC = c break end
end

local function mainSlots(p)
  local out = shell(LUAC .. ' -l -p "' .. ROOT .. p .. '" 2>&1')
  local slots = out:match("main <[^\n]*\n[^\n]-(%d+) slots")
  return tonumber(slots)
end

local function globalWrites(p)
  local names = {}
  if LUAC then
    local out = shell(LUAC .. ' -l -l -p "' .. ROOT .. p .. '" 2>&1')
    for name in out:gmatch('SETTABUP[^\n]-; _ENV "([%w_]+)"') do names[name] = true end
    for name in out:gmatch('SETGLOBAL[^\n]-; ([%w_]+)') do names[name] = true end
    local env, kstr = {}, {}
    for l in out:gmatch("[^\n]+") do
      if l:match("^%a+ <") then env, kstr = {}, {} end
      local op, a = l:match("^%s*%d+%s+%[%d+%]%s+(%u+)%s+(%d+)")
      if op and not op:match("^SET") then env[a], kstr[a] = nil, nil end
      local r = l:match("GETUPVAL%s+(%d+)%s+%d+%s*; _ENV")
      if r then env[r] = true end
      local kr, ks = l:match('LOADK%s+(%d+)%s+%d+%s*; "([%w_]+)"')
      if kr then kstr[kr] = ks end
      local ta, tb = l:match("SETTABLE%s+(%d+)%s+(%d+)")
      if ta and env[ta] and kstr[tb] then names[kstr[tb]] = true end
    end
  end
  for _, l in ipairs(fileLines(p)) do
    local n = code(l):match("_G%.([%w_]+)%s*=[^=]") or code(l):match('_G%[%s*"([%w_]+)"%s*%]%s*=[^=]')
    if n then names[n] = true end
  end
  return names
end

local base = {}
do
  local f = loadfile(BASELINE, "t", {})
  if f then base = f() or {} end
end
base.metrics = base.metrics or {}
local luacheckConfig = { files = {} }
assert(loadfile(ROOT .. ".luacheckrc", "t", luacheckConfig))()
local allow = {}
for _, n in ipairs(luacheckConfig.globals) do allow[n] = true end

local M = {}
local order = {}
local function metric(name, now, target, note, where, higherBetter)
  order[#order + 1] = name
  M[name] = { now = now, target = target, note = note, where = where, higherBetter = higherBetter }
end
local outsideCore = function(p) return not isCore(p) end

do
  local n, w = countCode(shipped, { "C_ChatInfo%.SendAddonMessage%s*[,(]" }, function(p) return p ~= "RavenquillExpedition/Comm.lua" end)
  metric("send_sites", n, 0, "SendAddonMessage calls outside core Comm.lua", w)
end
do
  local n, w = 0, {}
  for _, p in ipairs(shipped) do
    local ls = fileLines(p)
    for i, l in ipairs(ls) do
      local c = code(l)
      if c:find("hooksecurefunc%s*[,(]") and (c:find("SendAddonMessage") or code(ls[i + 1] or ""):find("SendAddonMessage")) then
        n = n + 1; w[#w + 1] = p .. ":" .. i
      end
    end
  end
  metric("send_hooks", n, 1, "hooksecurefunc on SendAddonMessage", w)
end
do
  local n, w = countCode(shipped, { "RegisterAddonMessagePrefix%s*[,(]" }, function(p) return p ~= "RavenquillExpedition/Comm.lua" end)
  metric("foreign_prefixes", n, 0, "prefixes registered outside core Comm.lua", w)
end
do
  local NAMES = { "IsSecret", "SafeCall", "UnitKey", "NormName", "StripRealm", "RealmSuffixes", "SurnameSeparator",
    "ReadRoster", "RequestRoster", "b36", "n36" }
  local n, w = 0, {}
  for _, p in ipairs(shipped) do
    if outsideCore(p) then
      local seen = {}
      for i, l in ipairs(fileLines(p)) do
        local c = code(l)
        for _, name in ipairs(NAMES) do
          if not seen[name] and c:find("function%s+[%w_.:]-" .. name .. "%w*%s*%(") then
            seen[name] = true; n = n + 1; w[#w + 1] = p .. ":" .. i .. " " .. name
          end
        end
        if not seen.CLASSES and c:find("CLASSES%s*=%s*{") then seen.CLASSES = true; n = n + 1; w[#w + 1] = p .. ":" .. i .. " CLASSES" end
        if not seen.DIGITS and c:find('DIGITS%s*=%s*"0123') then seen.DIGITS = true; n = n + 1; w[#w + 1] = p .. ":" .. i .. " DIGITS" end
      end
    end
  end
  metric("dup_primitives", n, 0, "core primitives re-implemented in modules", w)
end
do
  local n, w = countCode(shipped, { "Comm%.q%f[^%w_]", "Comm%.lastSent", "%.CommConst", "core%.Comm%f[^%w_]",
    "GS%.roster%f[^%w_]", "GS%.rosterRead", "core%.roster%f[^%w_]", "RQ%.roster%f[^%w_]" }, outsideCore, true)
  metric("core_internals", n, 0, "modules reading core internals", w)
end
do
  local best, where = 0, nil
  for _, p in ipairs(shipped) do
    local n = #fileLines(p)
    if n > best then best, where = n, p end
  end
  metric("max_file_lines", best, 1000, "largest shipped Lua file (" .. tostring(where) .. ")")
end
do
  local Health = dofile(ROOT .. "scripts/health.lua")
  local r = Health.analyze(shipped, function(p) return readFile(ROOT .. p) end)
  metric("health_clean_pct", r.cleanPct, 100, "functions within complexity/length/nesting limits, % (lua scripts/health.lua)", nil, true)
  metric("health_debt", r.debt, 0, "maintenance debt: excess complexity, length, nesting, file size (lua scripts/health.lua)")
  metric("max_fn_complexity", r.maxComplexity, 10, "highest cyclomatic complexity (" .. tostring(r.maxComplexityAt) .. ")")
end
if LUAC then
  local best, where = 0, nil
  for _, p in ipairs(shipped) do
    local s = mainSlots(p)
    if s and s > best then best, where = s, p end
  end
  metric("main_slots", best, 120, "register slots of the fullest main chunk, limit 200 (" .. tostring(where) .. ")")
else
  metric("main_slots", nil, 120, "luac not found (set LUAC)")
end
do
  local bad, w = 0, {}
  for _, p in ipairs(shipped) do
    for name in pairs(globalWrites(p)) do
      if not allow[name] then bad = bad + 1; w[#w + 1] = p .. " " .. name end
    end
  end
  metric("global_writes", bad, 0, "global writes outside the .luacheckrc globals" .. (LUAC and "" or " (luac missing: _G only)"), w)
end
do
  local files = {}
  for _, p in ipairs(devFiles) do files[#files + 1] = p end
  for _, p in ipairs(scriptFiles) do files[#files + 1] = p end
  local n, w = 0, {}
  for _, p in ipairs(files) do
    for i, l in ipairs(fileLines(p)) do
      if l:find("%f[%a]%a:[/\\]") or l:find("WTF[/\\]Account[/\\][^*/\\%s\"'$]") or l:find("AppData") or l:find("/Users/") then
        n = n + 1; w[#w + 1] = p .. ":" .. i
      end
    end
  end
  metric("dev_abs_paths", n, 0, "machine-specific paths in dev/ and scripts/", w)
end
do
  local pats = { "PLAN%.md", "HANDOFF%.md", "%f[%a]plan [%u%d]", "%(plan ", "review #%d", "F#%d", "%f[%w][FGHIJKLMW]%d+[%./]%w" }
  local commentPats = { "%f[%w][A-Z]%d%d?%f[^%w]", "post%-review", "[Uu]ser,? 20%d%d%-" }
  local n, w = 0, {}
  for _, p in ipairs(shipped) do
    for i, l in ipairs(fileLines(p)) do
      local hit = false
      for _, pat in ipairs(pats) do if l:find(pat) then hit = true; break end end
      local c = l:match("%-%-(.*)$")
      if c and not hit then for _, pat in ipairs(commentPats) do if c:find(pat) then hit = true; break end end end
      if hit then n = n + 1; w[#w + 1] = p .. ":" .. i end
    end
  end
  metric("plan_refs", n, 0, "comments pointing at git-ignored notes (PLAN.md, plan codes, dated user notes)", w)
end
local function luaCommentLines(src)
  local found, i, n, line = {}, 1, #src, 1
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then line = line + 1; i = i + 1
    elseif src:sub(i, i + 1) == "--" then
      found[#found + 1] = line
      local eq = src:match("^%[(=*)%[", i + 2)
      local e = eq and select(2, src:find("]" .. eq .. "]", i + 4 + #eq, true)) or (src:find("\n", i, true) or n + 1) - 1
      for _ in src:sub(i, e):gmatch("\n") do line = line + 1 end
      i = e + 1
    elseif c == "[" and src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      local e = select(2, src:find("]" .. eq .. "]", i + 2 + #eq, true)) or n
      for _ in src:sub(i, e):gmatch("\n") do line = line + 1 end
      i = e + 1
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n and src:sub(j, j) ~= c and src:sub(j, j) ~= "\n" do
        j = j + (src:sub(j, j) == "\\" and 2 or 1)
      end
      i = j + 1
    else i = i + 1 end
  end
  return found
end
do
  local HASH = { sh = true, ps1 = true, yml = true, yaml = true, toc = true }
  local DOT = { [".gitignore"] = true, [".gitattributes"] = true, [".editorconfig"] = true }
  local n, w = 0, {}
  for _, p in ipairs(all) do
    if not (p:match("/libs/") or p:match("/fixtures/compat_")) then
      local ext = p:match("%.([%w]+)$")
      if ext == "lua" or p == ".luacheckrc" then
        for _, l in ipairs(luaCommentLines(readFile(ROOT .. p) or "")) do n = n + 1; w[#w + 1] = p .. ":" .. l end
      elseif HASH[ext] or DOT[p] then
        for i, l in ipairs(fileLines(p)) do
          local full = l:match("^%s*#") and not l:match("^#!") and not l:match("^##")
          if full or l:match("%S%s%s+#%s") or l:match("^%s*<#") then n = n + 1; w[#w + 1] = p .. ":" .. i end
        end
      end
    end
  end
  metric("comments", n, 0, "comments in the codebase (none allowed; libs/ and compat fixtures exempt)", w)
end
do
  local n, w = 0, {}
  for _, p in ipairs(all) do
    local folder = p:match("^(RavenquillExpedition_[%w_]+)/%1%.toc$")
    if folder and folder ~= "RavenquillExpedition_Dev" then
      local deps = false
      for _, l in ipairs(fileLines(p)) do
        if l:match("^##%s*Dependencies:") and l:find("RavenquillExpedition%f[^%w_]") then deps = true end
        if l:match("^##%s*RequiredDeps:") and l:find("RavenquillExpedition%f[^%w_]") then deps = true end
      end
      if not deps then n = n + 1; w[#w + 1] = folder end
    end
  end
  metric("no_core_dep", n, 0, "modules without ## Dependencies: RavenquillExpedition", w)
end
do
  local n, w = countCode(shipped, { "^%s*Ravenquill%w+DB%s*=", "GetLocale%s*%(", 'RegisterEvent%(%s*"ADDON_LOADED"',
    'RegisterEvent%(%s*"PLAYER_LOGIN"' }, outsideCore)
  metric("own_mechanisms", n, 0, "modules with their own SV init / locale pick / login frames", w)
end
do
  local n, w = countCode(shipped, { "SafeCall%(%s*GCA[.:]", "SafeCall%(%s*M[.:]", "SafeCall%(%s*H[.:]", "SafeCall%(%s*self[.:]",
    "SafeCall%(%s*UI[.:]", "pcall%(%s*PumpOnce" })
  metric("swallowed_errors", n, 0, "own code run under quiet calls (errors never reach BugSack)", w)
end
do
  local n, w = countCode(shipped, { 'version%s*=%s*"%d' })
  metric("version_literals", n, 0, "version strings hard-coded in Lua (the .toc is the source)", w)
end
do
  local n, w = countCode(shipped, { "=%s*[%w_]+[.:]Trace%s*$", "=%s*[%w_]+[.:]Trace%s*[,;]" })
  metric("cached_trace", n, 0, "a cached Trace function (misses the Dev addon's override)", w)
end
do
  local n, w = countCode(shipped, { "CraftersJournal", "QuestieDB", "Questie%f[^%w_]" }, nil, true)
  metric("foreign_addon_refs", n, 0, "runtime reads of other addons (Auctionator excepted)", w)
end
do
  local s = readFile(ROOT .. "templates/Module/Example.lua")
  local n
  if s then
    n = 0
    for _, l in ipairs(lines(s)) do if code(l):match("%S") then n = n + 1 end end
  end
  metric("goal_module_lines", n, 40, s and "code lines of templates/Module/Example.lua" or "goal not yet reached (no template yet)")
end
local ENV_SKIPS = { ["score:simgear-source"] = true, ["score:craftersjournal-source"] = true, ["ui:craftersjournal-source"] = true }
local envSkip = false
for name in (opts.skipnames or ""):gmatch("[^,]+") do if ENV_SKIPS[name] then envSkip = true end end
if envSkip then
  opts.checksNote = " (not compared: environment skips present)"
end
metric("checks_passed", opts.checks, nil, "passing harness checks (never lower)" .. (opts.checksNote or ""), nil, true)
if envSkip then M.checks_passed.uncompared = true end
metric("checks_skipped", opts.skips, 0, "skipped harness sections" .. (opts.skipnames and opts.skipnames ~= "" and (": " .. opts.skipnames) or ""))
if envSkip then M.checks_skipped.uncompared = true end
metric("luacheck_warnings", opts.luacheck, 0, opts.luacheck and "luacheck warnings" or "luacheck not run")

local worse, improved = {}, {}
local function fmt(v) return v == nil and "n/a" or tostring(v) end
print(("%-20s %9s %9s %8s  %s"):format("metric", "baseline", "now", "target", "status"))
print(string.rep("-", 72))
for _, name in ipairs(order) do
  local m = M[name]
  local b = base.metrics[name]
  local status
  if m.now == nil then status = "n/a"
  elseif m.uncompared then status = "not compared"
  elseif b == nil then status = "new"
  elseif (m.higherBetter and m.now < b) or (not m.higherBetter and m.now > b) then status = "WORSE"; worse[#worse + 1] = name
  elseif m.now ~= b then status = "improved"; improved[#improved + 1] = name
  else status = "ok" end
  if m.now ~= nil and m.target ~= nil and ((m.higherBetter and m.now >= m.target) or (not m.higherBetter and m.now <= m.target)) then
    status = status == "WORSE" and status or (status .. " (target reached)")
  end
  if name == "main_slots" and m.now and m.now > 198 then status = "WORSE (over 198: the 200-locals limit)"; worse[#worse + 1] = name end
  print(("%-20s %9s %9s %8s  %s"):format(name, fmt(b), fmt(m.now), fmt(m.target), status))
  print("    " .. m.note)
  if status:match("^WORSE") and m.where then
    for i = 1, math.min(#m.where, 10) do print("      " .. m.where[i]) end
  end
end
if os.getenv("ARCH_VERBOSE") then
  for _, name in ipairs(order) do
    local m = M[name]
    if m.where and m.where[1] then print(name .. ":"); for _, w in ipairs(m.where) do print("  " .. w) end end
  end
end

if opts.update or not next(base.metrics) then
  for _, name in ipairs(order) do
    local m, b = M[name], base.metrics[name]
    if m.now ~= nil and not m.uncompared then
      if b == nil then base.metrics[name] = m.now
      elseif m.higherBetter then base.metrics[name] = math.max(b, m.now)
      else base.metrics[name] = math.min(b, m.now) end
    end
  end
  local out = { "return {",
    "  metrics = {" }
  local names = {}
  for k in pairs(base.metrics) do if M[k] then names[#names + 1] = k end end
  table.sort(names)
  for _, k in ipairs(names) do out[#out + 1] = ("    %s = %s,"):format(k, tostring(base.metrics[k])) end
  out[#out + 1] = "  },"
  out[#out + 1] = "}"
  local f = assert(io.open(BASELINE, "wb"))
  f:write(table.concat(out, "\n"), "\n")
  f:close()
  print("baseline written: scripts/arch-baseline.lua")
end

if worse[1] then
  print("ARCHITECTURE CHECK FAILED: worse than baseline: " .. table.concat(worse, ", "))
  os.exit(1)
end
print(("architecture check ok (%d improved%s)"):format(#improved, improved[1] and ": " .. table.concat(improved, ", ") or ""))
