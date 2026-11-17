return function(addonDir)
  local name = addonDir:gsub("[/\\]+$", ""):match("([^/\\]+)$")
  local f = assert(io.open(addonDir:gsub("[/\\]+$", "") .. "/" .. name .. ".toc", "rb"), "no .toc for " .. addonDir)
  local out = {}
  for line in f:lines() do
    line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") and line:match("%.lua$") then out[#out + 1] = (line:gsub("\\", "/")) end
  end
  f:close()
  return out
end
