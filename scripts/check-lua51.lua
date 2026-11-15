-- Lua 5.1 syntax guard for every file the game loads (the suite's RavenquillExpedition*/ folders without dev/).
-- The game runs Lua 5.1; the tests run on 5.4 and luacheck parses 5.3 syntax under any std, so neither notices
-- `//`, bit operators (& | ~ << >>), `goto` or `::labels::`. This scanner skips strings and comments and reports
-- those tokens. run-tests.sh calls it; with luac5.1 installed (CI) it also runs `luac5.1 -p` on the same files.
-- Usage: lua scripts/check-lua51.lua [file ...]   (no files: every shipped .lua; prints the list for luac with --list)
local function Scan(src)
  local probs, i, n, line = {}, 1, #src, 1
  local function prob(what) probs[#probs + 1] = ("%d: %s"):format(line, what) end
  local function skipTo(j) -- move to j, counting lines on the way
    local _, nl = src:sub(i, j - 1):gsub("\n", "")
    line, i = line + nl, j
  end
  while i <= n do
    local c, two = src:sub(i, i), src:sub(i, i + 1)
    if two == "--" then
      local eq = src:match("^%[(=*)%[", i + 2)
      if eq then
        local _, e = src:find("]" .. eq .. "]", i + 4 + #eq, true)
        skipTo((e or n) + 1)
      else
        skipTo(src:find("\n", i, true) or n + 1)
      end
    elseif c == "[" and src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      local _, e = src:find("]" .. eq .. "]", i + 2 + #eq, true)
      skipTo((e or n) + 1)
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == c or d == "\n" then break
        else j = j + 1 end
      end
      skipTo(j + 1)
    elseif c:match("[%a_]") then
      local w = src:match("^[%w_]+", i)
      if w == "goto" then prob("goto (Lua 5.2+)") end
      i = i + #w
    elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
      local num = src:match("^[%w%.]+", i)
      if num:match("[eE]$") and src:sub(i + #num, i + #num):match("[%+%-]") then
        num = num .. src:match("^[%+%-]%d*", i + #num)
      end
      i = i + #num
    elseif c == "\n" then
      line, i = line + 1, i + 1
    else
      if two == "//" then prob("// integer division (Lua 5.3+)"); i = i + 2
      elseif two == "<<" or two == ">>" then prob(two .. " shift (Lua 5.3+)"); i = i + 2
      elseif two == "::" then prob(":: label (Lua 5.2+)"); i = i + 2
      elseif two == "~=" then i = i + 2
      elseif c == "&" or c == "|" or c == "~" then prob(c .. " bit operator (Lua 5.3+)"); i = i + 1
      else i = i + 1 end
    end
  end
  return probs
end

-- What the game loads: every .lua a suite .toc names, and every <Script file> of an .xml it names (libraries).
local function ShippedFiles()
  local out, seen = {}, {}
  local function add(f) if not seen[f] then seen[f] = true; out[#out + 1] = f end end
  local function read(f) local h = io.open(f, "rb"); if not h then return nil end local s = h:read("*a"); h:close(); return s end
  local function xml(path)
    local s = read(path)
    if not s then return end
    local dir = path:match("^(.*/)") or ""
    for ref in s:gmatch('<Script%s+file="([^"]+)"') do add(dir .. ref:gsub("\\", "/")) end
    for ref in s:gmatch('<Include%s+file="([^"]+)"') do xml(dir .. ref:gsub("\\", "/")) end
  end
  local list = package.config:sub(1, 1) == "\\" and 'dir /b /ad "RavenquillExpedition*" 2>nul'
    or "ls -d RavenquillExpedition*/ 2>/dev/null"
  local p = io.popen(list)
  for d in p:lines() do
    d = d:gsub("[/\\]$", "")
    local toc = read(d .. "/" .. d .. ".toc")
    for entry in (toc or ""):gmatch("[^\r\n]+") do
      if not entry:match("^%s*#") then
        entry = entry:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
        if entry:match("%.lua$") then add(d .. "/" .. entry)
        elseif entry:match("%.xml$") then xml(d .. "/" .. entry) end
      end
    end
  end
  p:close()
  table.sort(out)
  return out
end

local files, list = {}, false
for _, a in ipairs(arg) do if a == "--list" then list = true else files[#files + 1] = a end end
if #files == 0 then files = ShippedFiles() end
if list then for _, f in ipairs(files) do print(f) end return end
local bad = 0
for _, f in ipairs(files) do
  local h = io.open(f, "rb")
  if h then
    local src = h:read("*a"); h:close()
    for _, p in ipairs(Scan(src)) do print(f .. ":" .. p); bad = bad + 1 end
  else
    print(f .. ": listed in a .toc but missing"); bad = bad + 1
  end
end
print(("lua 5.1 syntax: %d files, %d problems"):format(#files, bad))
os.exit(bad == 0 and 0 or 1)
