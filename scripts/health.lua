local H = {}

H.LIMITS = { complexity = 10, lines = 60, depth = 4, fileLines = 500 }

local KEYWORDS = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%a+") do
  KEYWORDS[w] = true
end

function H.tokens(src)
  local out, i, n, line = {}, 1, #src, 1
  local function skipTo(e)
    for _ in src:sub(i, e):gmatch("\n") do line = line + 1 end
    i = e + 1
  end
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then line = line + 1; i = i + 1
    elseif c:match("%s") then i = i + 1
    elseif src:sub(i, i + 1) == "--" then
      local eq = src:match("^%[(=*)%[", i + 2)
      local e = eq and select(2, src:find("]" .. eq .. "]", i + 4 + #eq, true)) or ((src:find("\n", i, true) or n + 1) - 1)
      skipTo(e)
    elseif c == "[" and src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      out[#out + 1] = { t = "string", line = line }
      skipTo(select(2, src:find("]" .. eq .. "]", i + 2 + #eq, true)) or n)
    elseif c == '"' or c == "'" then
      out[#out + 1] = { t = "string", line = line }
      local j = i + 1
      while j <= n and src:sub(j, j) ~= c and src:sub(j, j) ~= "\n" do j = j + (src:sub(j, j) == "\\" and 2 or 1) end
      i = j + 1
    elseif c:match("[%a_]") then
      local w = src:match("^[%w_]+", i)
      out[#out + 1] = { t = KEYWORDS[w] and w or "name", v = w, line = line }
      i = i + #w
    elseif c:match("%d") then
      local w = src:match("^0[xX]%x+", i) or src:match("^%d*%.?%d+[eE][%+%-]?%d+", i) or src:match("^%d*%.?%d*", i)
      out[#out + 1] = { t = "number", line = line }
      i = i + math.max(1, #w)
    else
      local op = src:match("^%.%.%.", i) or src:match("^[=~<>]=", i) or src:match("^%.%.", i) or src:match("^::", i) or c
      out[#out + 1] = { t = op, line = line }
      i = i + #op
    end
  end
  return out
end

local function functionName(toks, k)
  local parts = {}
  local j = k + 1
  while toks[j] and toks[j].t ~= "(" do
    parts[#parts + 1] = toks[j].v or toks[j].t
    j = j + 1
  end
  if #parts > 0 then return table.concat(parts) end
  local prev, before = toks[k - 1], toks[k - 2]
  if prev and prev.t == "=" and before and before.v then return before.v end
  if prev and prev.t == "(" and before and before.v then return "<" .. before.v .. " callback>" end
  return "<anonymous>"
end

function H.functions(src)
  local toks = H.tokens(src)
  local fns, stack, pendingLoop = {}, {}, false
  local function current()
    for s = #stack, 1, -1 do if stack[s].fn then return stack[s].fn, s end end
  end
  local function depthIn(fnIndex)
    local d = 0
    for s = fnIndex + 1, #stack do if stack[s].nest then d = d + 1 end end
    return d
  end
  local function bump()
    local fn = current()
    if fn then fn.complexity = fn.complexity + 1 end
  end
  local function push(entry)
    stack[#stack + 1] = entry
    local fn, idx = current()
    if fn and entry.nest then fn.depth = math.max(fn.depth, depthIn(idx)) end
  end
  local function pop(line)
    local e = table.remove(stack)
    if e and e.fn then e.fn.last = line; fns[#fns + 1] = e.fn end
  end
  for k, tk in ipairs(toks) do
    local t = tk.t
    if t == "function" then
      push({ fn = { name = functionName(toks, k), first = tk.line, complexity = 1, depth = 0 } })
    elseif t == "if" then bump(); push({ nest = true })
    elseif t == "elseif" or t == "and" or t == "or" then bump()
    elseif t == "for" or t == "while" then bump(); pendingLoop = true
    elseif t == "do" then push({ nest = pendingLoop }); pendingLoop = false
    elseif t == "repeat" then bump(); push({ nest = true, rep = true })
    elseif t == "end" or t == "until" then pop(tk.line)
    end
  end
  for _, fn in ipairs(fns) do fn.lines = fn.last - fn.first + 1 end
  return fns
end

function H.analyze(files, read)
  local L = H.LIMITS
  local r = { functions = 0, clean = 0, debt = 0, complexFns = 0, longFns = 0, deepFns = 0, maxComplexity = 0,
    maxComplexityAt = nil, codeLines = 0, files = #files, hotspots = {} }
  for _, path in ipairs(files) do
    local src = read(path) or ""
    local lines = 0
    for l in (src .. "\n"):gmatch("([^\n]*)\n") do if l:find("%S") then lines = lines + 1 end end
    r.codeLines = r.codeLines + lines
    r.debt = r.debt + math.max(0, lines - L.fileLines) / 20
    for _, fn in ipairs(H.functions(src)) do
      r.functions = r.functions + 1
      local over = math.max(0, fn.complexity - L.complexity)
      local long = math.max(0, fn.lines - L.lines)
      local deep = math.max(0, fn.depth - L.depth)
      local cost = over + long / 10 + deep * 3
      r.debt = r.debt + cost
      if over > 0 then r.complexFns = r.complexFns + 1 end
      if long > 0 then r.longFns = r.longFns + 1 end
      if deep > 0 then r.deepFns = r.deepFns + 1 end
      if cost == 0 then r.clean = r.clean + 1 end
      if fn.complexity > r.maxComplexity then
        r.maxComplexity, r.maxComplexityAt = fn.complexity, path .. ":" .. fn.first .. " " .. fn.name
      end
      if cost > 0 then
        r.hotspots[#r.hotspots + 1] = { cost = cost, where = path .. ":" .. fn.first, name = fn.name,
          complexity = fn.complexity, lines = fn.lines, depth = fn.depth }
      end
    end
  end
  r.debt = math.floor(r.debt * 10 + 0.5) / 10
  r.cleanPct = r.functions > 0 and math.floor(r.clean / r.functions * 1000 + 0.5) / 10 or 100
  table.sort(r.hotspots, function(a, b) return a.cost > b.cost end)
  return r
end

function H.shippedFiles(root)
  local p = io.popen('git -C "' .. root .. '" ls-files --cached --others --exclude-standard')
  local files = {}
  for f in p:read("*a"):gmatch("[^\r\n]+") do
    if f:match("^RavenquillExpedition[%w_]*/") and f:match("%.lua$") and not f:match("/dev/") and not f:match("/libs/")
      and not f:match("/Data/") and not f:match("^RavenquillExpedition_Dev/") then
      local h = io.open(root .. f, "rb")
      if h then h:close(); files[#files + 1] = f end
    end
  end
  p:close()
  table.sort(files)
  return files
end

if arg and arg[0] and arg[0]:match("health%.lua$") then
  local root = (arg[0]:gsub("[^/\\]*$", "")) .. "../"
  local top = tonumber(arg[1]) or 15
  local function read(f) local h = io.open(root .. f, "rb"); if not h then return nil end; local s = h:read("*a"); h:close(); return s end
  local r = H.analyze(H.shippedFiles(root), read)
  print(("Codebase health (shipped Lua, %d files, %d code lines, %d functions)"):format(r.files, r.codeLines, r.functions))
  print(("  clean functions   %5.1f %%   (complexity <= %d, <= %d lines, nesting <= %d)"):format(r.cleanPct,
    H.LIMITS.complexity, H.LIMITS.lines, H.LIMITS.depth))
  print(("  maintenance debt  %7.1f    (lower is better)"):format(r.debt))
  print(("  too complex %d, too long %d, too deep %d; worst complexity %d at %s"):format(r.complexFns, r.longFns,
    r.deepFns, r.maxComplexity, tostring(r.maxComplexityAt)))
  print(("Top %d hotspots (debt, complexity, lines, nesting):"):format(top))
  for i = 1, math.min(top, #r.hotspots) do
    local h = r.hotspots[i]
    print(("  %6.1f  cc %3d  %4d lines  depth %d  %s %s"):format(h.cost, h.complexity, h.lines, h.depth, h.where, h.name))
  end
end

return H
