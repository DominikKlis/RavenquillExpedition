local Golden = {}

local function load(path)
  local f = loadfile(path, "t", {})
  if not f then return nil end
  local ok, t = pcall(f)
  return ok and type(t) == "table" and t or nil
end

function Golden.open(path, record)
  local g = { path = path, record = record, data = record and {} or load(path), missing = false }
  if not g.data then g.data, g.missing = {}, true end

  function g:compare(name, list, check)
    if self.record then
      self.data[name] = list
      check(true, "recorded golden " .. name .. " (" .. #list .. " lines)")
      return
    end
    local want = self.data[name]
    if not want then
      check(false, "golden " .. name .. " missing in " .. self.path .. " (run the harness with --record)")
      return
    end
    local diffs = {}
    for i = 1, math.max(#want, #list) do
      if want[i] ~= list[i] then
        diffs[#diffs + 1] = ("    #%d want %s\n    #%d got  %s"):format(i, tostring(want[i]), i, tostring(list[i]))
        if #diffs >= 5 then break end
      end
    end
    if diffs[1] then print(table.concat(diffs, "\n")) end
    check(not diffs[1], ("golden %s: %d lines byte-identical"):format(name, #want))
  end

  function g:finish()
    if not self.record then return end
    local names = {}
    for k in pairs(self.data) do names[#names + 1] = k end
    table.sort(names)
    local out = { "-- Golden fixture. Recorded by the harness with --record; never edit by hand.", "return {" }
    for _, k in ipairs(names) do
      out[#out + 1] = ("  [%q] = {"):format(k)
      for _, s in ipairs(self.data[k]) do out[#out + 1] = ("    %q,"):format(s) end
      out[#out + 1] = "  },"
    end
    out[#out + 1] = "}"
    local f = assert(io.open(self.path, "wb"))
    f:write(table.concat(out, "\n"), "\n")
    f:close()
    print("recorded " .. self.path)
  end
  return g
end

function Golden.Serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "string" then return ("%q"):format(v) end
  if t ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) == "number"
  end)
  if not keys[1] then return "{}" end
  local out = { "{" }
  for _, k in ipairs(keys) do
    local ks = type(k) == "string" and ("[%q]"):format(k) or ("[" .. tostring(k) .. "]")
    out[#out + 1] = indent .. "  " .. ks .. " = " .. Golden.Serialize(v[k], indent .. "  ") .. ","
  end
  out[#out + 1] = indent .. "}"
  return table.concat(out, "\n")
end

return Golden
