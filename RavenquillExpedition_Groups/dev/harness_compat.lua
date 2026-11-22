local DIR = (arg[0]:gsub("[^/\\]*$", ""))
local GK = dofile(DIR .. "groupkit.lua")
local Kit = GK.Kit
local check, section = Kit.check, Kit.section
local Golden = dofile(DIR .. "../../RavenquillExpedition/dev/golden.lua")
local RECORD = arg[1] == "--record"
local gold = Golden.open(DIR .. "fixtures/compat_golden.lua", RECORD)

local T0 = 1763100000
local function Roles(t, h, d) return { tn = t[1], th = t[2], hn = h[1], hh = h[2], dn = d[1], dh = d[2] } end
local function Post(over)
  local m = { poster = "Hanne Moosgrund", id = T0, t = T0 + 120, act = "smcath", note = "" }
  for k, v in pairs(Roles({ 1, 0 }, { 1, 1 }, { 3, 1 })) do m[k] = v end
  for k, v in pairs(over or {}) do m[k] = v end
  return m
end
local CASES = {
  { "p", Post({ note = "Bitte mit Heiltränken" }) },
  { "p", Post({ poster = "Mira Sturmfeder", act = "mc", when = T0 + 2 * 86400, note = "Einstimmung nötig",
    tn = 4, th = 2, hn = 8, hh = 5, dn = 28, dh = 7 }) },
  { "p", Post({ act = "ubrs", tn = 2, hn = 2, dn = 6, note = string.rep("Langer Text; mit | Strich ", 4) }) },
  { "s", { poster = "Hanne Moosgrund", id = T0, role = "d", again = false } },
  { "s", { poster = "Mira Sturmfeder", id = T0, role = "t", again = true } },
  { "x", { id = T0 } },
  { "q", {} },
}

section("Encoder layer: channel GF")
local sched, bus = Kit.Setup()
local probe = GK.Client(sched, bus, "Bert Hill", { random = Kit.Random(4242) })
probe.login()
sched:advance(5)
local ch = probe.Sync.channel
local encoded = {}
for _, c in ipairs(CASES) do encoded[#encoded + 1] = ch:Encode(c[1], c[2]) or "<nil>" end
gold:compare("groups.encode", encoded, check)

section("Decoder layer")
local goldEnc = RECORD and encoded or (gold.data["groups.encode"] or {})
local same = 0
for i, c in ipairs(CASES) do
  local typ, m = ch:Decode("Bert Hill", (goldEnc[i] or ""):match("^GF;(.*)$"))
  local ok = typ == c[1]
  for k, v in pairs(c[2]) do
    if k ~= "note" and m and m[k] ~= v then ok = false end
  end
  if ok then same = same + 1 end
end
check(same == #CASES, ("%d/%d golden GF messages decode to what was sent"):format(same, #CASES))
local _, long = ch:Decode("Bert Hill", goldEnc[3]:match("^GF;(.*)$"))
check(long and #long.note == 60 and not long.note:find("[;|]"), "a 104-byte note arrives cut to 60 bytes, without ; or |")

section("Scenario layer: post, sign-up, late login, close")
local t0
do
  local s2, b2, _, by = GK.Guild({ { "Hanne Moosgrund", "ROGUE", 39 }, { "Bert Hill", "WARRIOR", 40 } })
  t0 = s2.t
  local hanne, bert = by["Hanne Moosgrund"], by["Bert Hill"]
  hanne.G:Post(GK.Spec(hanne, "smcath", { heal = 1, dps = 1 }, { note = "Bitte mit Heiltränken" }))
  s2:advance(30)
  bert.G:SignUp("Hanne Moosgrund", "dps")
  s2:advance(30)
  GK.Join(s2, b2, { "Cora Vale", "PRIEST", 38 }, { seed = 5 })
  s2:advance(120)
  hanne.G:Close()
  s2:advance(30)
  local lines = {}
  for _, e in ipairs(GK.Wire(b2)) do
    if e.t >= t0 then lines[#lines + 1] = ("%07.1f %s|%s"):format(e.t - t0, e.sender, e.msg) end
  end
  check(#lines == 5, ("scenario: %d GF messages (post, sign-up, ask, answer, close)"):format(#lines))
  gold:compare("groups.scenario", lines, check)

  section("SavedVariables layer")
  local function SplitLines(s) local out = {} for l in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = l end return out end
  hanne.G:Post(GK.Spec(hanne, "mc", { tank = 2 }, { when = hanne.RQ:Now() + 86400, note = "Einstimmung nötig" }))
  s2:advance(30)
  bert.G:SignUp("Hanne Moosgrund", "heal")
  s2:advance(30)
  gold:compare("sv.poster", SplitLines(Golden.Serialize(hanne.env.RavenquillExpeditionGroupsDB)), check)
  gold:compare("sv.signer", SplitLines(Golden.Serialize(bert.env.RavenquillExpeditionGroupsDB)), check)
  local back = GK.Join(s2, b2, { "Hanne Moosgrund", "ROGUE", 39 }, { sv = hanne.env.RavenquillExpeditionGroupsDB, seed = 9 })
  s2:advance(5)
  local own = back.G:OwnPost()
  check(own and own.activity == "mc" and own.signups[1] and own.signups[1].who == "Bert Hill" and #back.errors == 0,
    "the saved shape loads back: Hanne's raid with Bert's sign-up after a relog")
end

gold:finish()
Kit.finish()
