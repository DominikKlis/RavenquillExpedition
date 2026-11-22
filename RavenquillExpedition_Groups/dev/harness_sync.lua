local GK = dofile((arg[0]:gsub("[^/\\]*$", "")) .. "groupkit.lua")
local Kit = GK.Kit
local check, section = Kit.check, Kit.section
local Spec, PostOf, Counts, Wire, Since = GK.Spec, GK.PostOf, GK.Counts, GK.Wire, GK.Since

local HANNE = { "Hanne Moosgrund", "ROGUE", 39, "Arathihochland" }
local BERT = { "Bert Hill", "WARRIOR", 40, "Alteracgebirge" }
local CORA = { "Cora Vale", "PRIEST", 20, "Brachland" }
local MIRA = { "Mira Sturmfeder", "PRIEST", 60, "Östliche Pestländer" }

local function NoErrors(cs, more)
  local all = {}
  for _, c in ipairs(cs) do all[#all + 1] = c end
  for _, c in ipairs(more or {}) do all[#all + 1] = c end
  for _, c in ipairs(all) do
    if #c.errors > 0 then return check(false, "no Lua errors (" .. c.name .. ": " .. tostring(c.errors[1]) .. ")") end
  end
  return check(true, "no Lua errors")
end

section("A post reaches every guildmate")
local sched, bus, cs, by = GK.Guild({ HANNE, BERT, CORA })
local hanne, bert, cora = by["Hanne Moosgrund"], by["Bert Hill"], by["Cora Vale"]
local t0 = sched.t
local post = hanne.G:Post(Spec(hanne, "smcath", { heal = 1, dps = 1 }, { note = "Bitte mit Heiltränken" }))
sched:advance(10)
local atBert, atCora = PostOf(bert, "Hanne Moosgrund"), PostOf(cora, "Hanne Moosgrund")
check(atBert and atBert.activity == "smcath" and atBert.kind == "dungeon" and atBert.note == "Bitte mit Heiltränken"
  and atBert.id == post.id and atBert.expires == post.t + 3600,
  "Bert holds Hanne's post: Kathedrale, a dungeon, her note, expiring an hour after posting")
check(Counts(atBert) == "0/1 1/1 1/3" and Counts(atCora) == "0/1 1/1 1/3",
  "both guildmates see the roles: tank 0/1, healer 1/1, dps 1/3 (" .. Counts(atBert) .. ")")
check(#Wire(bus, Since(t0)) == 1 and #Wire(bus, Since(t0, "p", "Hanne Moosgrund")) == 1, "posting costs one message")
check(bert.printedMatch("Hanne Moosgrund sucht für Scharlachrotes Kloster: Kathedrale: Tank, Schaden.") ~= nil,
  "Bert (40, inside 35-45) gets one chat line naming the open roles")
check(cora.printedMatch("Hanne Moosgrund sucht") == nil and hanne.printedMatch("Hanne Moosgrund sucht") == nil,
  "Cora (20) and Hanne herself get no chat line")

section("A sign-up reaches the poster and fills the slot for everyone")
t0 = sched.t
check(bert.G:SignUp("Hanne Moosgrund", "dps"), "Bert signs up as dps")
sched:advance(10)
local w = bert.whispers[1]
check(#bert.whispers == 1 and w.kind == "WHISPER" and w.target == "Hanne Moosgrund"
  and w.msg == "Hallo! Ich melde mich für Scharlachrotes Kloster: Kathedrale an, als Schaden. (Ravenquill)",
  "and whispers Hanne: " .. tostring(w and w.msg))
local own = PostOf(hanne, "Hanne Moosgrund")
check(#own.signups == 1 and own.signups[1].who == "Bert Hill" and own.signups[1].role == "dps",
  "Hanne's post lists Bert as dps")
check(Counts(own) == "0/1 1/1 2/3" and Counts(PostOf(cora, "Hanne Moosgrund")) == "0/1 1/1 2/3",
  "dps reads 2/3 at Hanne and at Cora")
check(hanne.printedMatch("Bert Hill meldet sich als Schaden an.") ~= nil, "Hanne gets a chat line about the sign-up")
check(#Wire(bus, Since(t0)) == 1 and #Wire(bus, Since(t0, "s", "Bert Hill")) == 1, "a sign-up costs one message")
check(not bert.G:SignUp("Hanne Moosgrund", "tank") and not cora.G:SignUp("Hanne Moosgrund", "heal"),
  "no second sign-up from Bert, no sign-up for the full healer slot")
check(not hanne.G:SignUp("Hanne Moosgrund", "tank"), "no sign-up for your own post")
sched:advance(10)
check(#Wire(bus, Since(t0)) == 1 and Counts(PostOf(cora, "Hanne Moosgrund")) == "0/1 1/1 2/3",
  "refused sign-ups send nothing and count nothing")
hanne.G:Invite("Bert Hill")
check(hanne.invites[1] == "Bert Hill", "Hanne invites Bert by name with the game's invite")
NoErrors(cs)

section("Passt zu deiner Stufe")
local cath = hanne.A.Get("smcath")
check(hanne.A.Fits(cath, 35) and hanne.A.Fits(cath, 45) and not hanne.A.Fits(cath, 34) and not hanne.A.Fits(cath, 46),
  "Kathedrale fits levels 35 to 45 and nothing outside")
check(bert.G:Fits(PostOf(bert, "Hanne Moosgrund")) and not cora.G:Fits(PostOf(cora, "Hanne Moosgrund")),
  "Hanne's post fits Bert (40), not Cora (20)")
check(not bert.A.Fits(bert.A.Get("mc"), 59) and bert.A.Fits(bert.A.Get("mc"), 60), "a raid fits only level 60")

section("Replacement: a poster's newer version wins")
t0 = sched.t
hanne.G:Post(Spec(hanne, "smcath", { tank = 1, heal = 1, dps = 2 }, { note = "Tank gefunden" }))
sched:advance(10)
atBert = PostOf(bert, "Hanne Moosgrund")
check(atBert.id == post.id and atBert.t > post.t and Counts(atBert) == "1/1 1/1 2/3" and atBert.note == "Tank gefunden",
  "an edit of the same dungeon keeps the post (same id), newer version: tank 1/1, new note")
check(#PostOf(hanne, "Hanne Moosgrund").signups == 1 and bert.G:MySignup(atBert) ~= nil,
  "the edit keeps Bert's sign-up at Hanne and at Bert")
local oldText = bert.Sync.channel:Encode("p", bert.Sync.ToMessage(post))
GK.Hear(cora, "Bert Hill", oldText)
check(Counts(PostOf(cora, "Hanne Moosgrund")) == "1/1 1/1 2/3", "a late relay of the older version changes nothing")
hanne.G:Post(Spec(hanne, "scholo", { tank = 1 }))
sched:advance(10)
atBert = PostOf(bert, "Hanne Moosgrund")
local posts = 0
for poster in pairs(bert.G:GuildStore("posts")) do if poster == "Hanne Moosgrund" then posts = posts + 1 end end
check(atBert.activity == "scholo" and atBert.id > post.id and posts == 1 and #atBert.signups == 0,
  "posting another dungeon replaces the post: one post per poster, sign-ups start over")
check(bert.G:MySignup(atBert) == nil and next(bert.G:GuildStore("mine")) == nil,
  "Bert's sign-up for the Kathedrale is gone with it")
check(#Wire(bus, Since(t0)) == 2, "two edits, two messages")

section("Closing and expiry")
local scholo = PostOf(hanne, "Hanne Moosgrund")
local scholoText = hanne.Sync.channel:Encode("p", hanne.Sync.ToMessage(scholo))
t0 = sched.t
hanne.G:Close()
sched:advance(10)
check(PostOf(bert, "Hanne Moosgrund") == nil and PostOf(cora, "Hanne Moosgrund") == nil and hanne.G:OwnPost() == nil,
  "a closed post disappears everywhere")
check(#Wire(bus, Since(t0, "x", "Hanne Moosgrund")) == 1 and #Wire(bus, Since(t0)) == 1, "closing costs one message")
GK.Hear(cora, "Bert Hill", scholoText)
check(PostOf(cora, "Hanne Moosgrund") == nil, "a relay of the closed post does not bring it back")
local again = hanne.G:Post(Spec(hanne, "scholo", {}))
sched:advance(10)
check(again.id > scholo.id and PostOf(cora, "Hanne Moosgrund") and PostOf(cora, "Hanne Moosgrund").id == again.id,
  "a new post after closing gets a newer id and shows again")
local born = again.t
sched:advance(born + 3600 - 1 - hanne.RQ:Now())
check(#cora.G:ActivePosts() == 1, "one second before its hour is up the post is still listed")
sched:advance(2)
check(#cora.G:ActivePosts() == 0 and #hanne.G:ActivePosts() == 0, "after an hour it is gone from every list")
sched:advance(31)
check(PostOf(cora, "Hanne Moosgrund") == nil and PostOf(hanne, "Hanne Moosgrund") == nil,
  "and the next tick drops it from SavedVariables")
NoErrors(cs)

section("Late login: active posts reach a guildmate who logs in later")
sched, bus, cs, by = GK.Guild({ HANNE, BERT, CORA, MIRA })
hanne, bert, cora = by["Hanne Moosgrund"], by["Bert Hill"], by["Cora Vale"]
local mira = by["Mira Sturmfeder"]
hanne.G:Post(Spec(hanne, "smcath", { heal = 1, dps = 1 }))
local raidAt = mira.RQ:Now() + 2 * 86400
mira.G:Post(Spec(mira, "mc", { tank = 2, heal = 5, dps = 7 }, { when = raidAt, note = "Einstimmung nötig" }))
sched:advance(10)
bert.G:SignUp("Hanne Moosgrund", "dps")
sched:advance(10)
GK.Leave(bus, mira)
sched:advance(600)
t0 = sched.t
local dora = GK.Join(sched, bus, { "Dora Dunn", "MAGE", 38, "Tanaris" })
sched:advance(120)
local raid = PostOf(dora, "Mira Sturmfeder")
check(PostOf(dora, "Hanne Moosgrund") and Counts(PostOf(dora, "Hanne Moosgrund")) == "0/1 1/1 2/3",
  "Dora, logging in later, sees Hanne's post with Bert's sign-up counted (" .. Counts(PostOf(dora, "Hanne Moosgrund")) .. ")")
check(raid and raid.kind == "raid" and raid.when == raidAt and raid.note == "Einstimmung nötig" and Counts(raid) == "2/4 5/8 7/28",
  "and Mira's raid, although Mira is offline: a guildmate who holds it answers")
local late = Wire(bus, Since(t0))
local asks, answers = #Wire(bus, Since(t0, "q")), #Wire(bus, Since(t0, "p"))
check(asks == 1 and answers == 2 and #late == 3,
  ("the late login costs 1 ask + 1 answer per active post: %d asks, %d answers"):format(asks, answers))
check(#Wire(bus, Since(t0, "p", "Hanne Moosgrund")) == 1, "the poster answers her own post first; nobody repeats it")
NoErrors(cs, { dora })

section("A sign-up for a poster who is offline reaches her when she is back")
t0 = sched.t
check(bert.G:SignUp("Mira Sturmfeder", "tank"), "Bert signs up for Mira's raid while she is offline")
sched:advance(10)
check(#bert.whispers == 1, "no whisper to a poster who is offline (only the earlier one to Hanne)")
check(Counts(PostOf(cora, "Mira Sturmfeder")) == "3/4 5/8 7/28" and Counts(PostOf(dora, "Mira Sturmfeder")) == "3/4 5/8 7/28",
  "the guildmates online count Bert's sign-up right away")
local miraSv = GK.Copy(mira.env.RavenquillExpeditionGroupsDB)
sched:advance(300)
local erik = GK.Join(sched, bus, { "Erik Eiche", "HUNTER", 60, "Silithus" }, { seed = 3 })
sched:advance(120)
check(Counts(PostOf(erik, "Mira Sturmfeder")) == "3/4 5/8 7/28" and erik.G:GuildStore("posts")["Mira Sturmfeder"].signups[1] == nil,
  "Erik logs in later still: he gets the raid by relay, Bert already counted, without the names")
sched:advance(180)
local mira2 = GK.Join(sched, bus, MIRA, { sv = miraSv, seed = 7 })
sched:advance(120)
local miraOwn = mira2.G:OwnPost()
check(miraOwn and miraOwn.when == raidAt and miraOwn.signups[1] and miraOwn.signups[1].who == "Bert Hill"
  and miraOwn.signups[1].role == "tank" and Counts(miraOwn) == "3/4 5/8 7/28",
  "Mira, back online with her saved post, receives Bert's sign-up again and lists him as tank")
check(#Wire(bus, Since(t0, "s", "Bert Hill")) == 2, "the sign-up went out twice: once when made, once when Mira was back")
check(Counts(PostOf(cora, "Mira Sturmfeder")) == "3/4 5/8 7/28" and Counts(PostOf(dora, "Mira Sturmfeder")) == "3/4 5/8 7/28"
  and Counts(PostOf(erik, "Mira Sturmfeder")) == "3/4 5/8 7/28",
  "the repeat is not counted twice by the others, not even by Erik, who never heard the first one")
sched:advance(3600)
check(#Wire(bus, Since(sched.t - 3000, "s")) == 0, "and is sent only once")
NoErrors(cs, { dora, mira2, erik })

section("Message cost: bounded and silent when nothing happens")
t0 = sched.t
sched:advance(3600)
check(#Wire(bus, Since(t0)) == 0, "an hour with two active posts and five clients: no messages at all (no heartbeat)")
local burst = sched.t
for i = 1, 12 do mira2.G:Post(Spec(mira2, "mc", { tank = 2, heal = 5, dps = 7 }, { when = raidAt, note = "Stand " .. i })) end
sched:advance(600)
local perMin = bus:maxPer(60, "Mira Sturmfeder")
local sent = #Wire(bus, Since(burst, "p", "Mira Sturmfeder"))
check(perMin <= 15 and sent <= 12 and PostOf(bert, "Mira Sturmfeder").note == "Stand 12",
  ("twelve quick edits: %d messages, at most %d in any 60 s (<= 15), the last edit arrives"):format(sent, perMin))
NoErrors(cs)

section("Combat and instances: the post goes out afterwards")
sched, bus, cs, by = GK.Guild({ HANNE, BERT })
hanne, bert = by["Hanne Moosgrund"], by["Bert Hill"]
t0 = sched.t
hanne.combat = true
hanne.G:Post(Spec(hanne, "smcath", {}))
sched:advance(60)
check(PostOf(bert, "Hanne Moosgrund") == nil and #Wire(bus, Since(t0)) == 0, "in combat nothing is sent")
hanne.combat = false
hanne.fire("PLAYER_REGEN_ENABLED")
sched:advance(10)
check(PostOf(bert, "Hanne Moosgrund") ~= nil, "after combat the post goes out")
hanne.instance = true
hanne.fire("PLAYER_ENTERING_WORLD", false, false)
hanne.G:Post(Spec(hanne, "smcath", { tank = 1 }))
sched:advance(60)
check(Counts(PostOf(bert, "Hanne Moosgrund")) == "0/1 0/1 0/3", "inside an instance the edit waits")
hanne.instance = false
hanne.fire("PLAYER_ENTERING_WORLD", false, false)
sched:advance(10)
check(Counts(PostOf(bert, "Hanne Moosgrund")) == "1/1 0/1 0/3", "back outside it goes out")
NoErrors(cs)

section("Messages that are rejected")
local ch, rejected = bert.Sync.channel, bert.Sync.state.rejected
local now = bert.RQ:Now()
local function Msg(over)
  now = bert.RQ:Now()
  local m = { poster = "Hanne Moosgrund", id = now, t = now, act = "smcath", note = "", tn = 1, th = 0, hn = 1, hh = 0, dn = 3, dh = 0 }
  for k, v in pairs(over) do m[k] = v end
  return ch:Encode("p", m)
end
local before = GK.Copy(PostOf(bert, "Hanne Moosgrund"))
GK.Hear(bert, "Hanne Moosgrund", Msg({ act = "ragna" }))
GK.Hear(bert, "Hanne Moosgrund", Msg({ th = 2 }))
GK.Hear(bert, "Hanne Moosgrund", Msg({ tn = 0, hn = 0, dn = 0 }))
GK.Hear(bert, "Hanne Moosgrund", Msg({ act = "mc", when = now + 9 * 86400, tn = 4, hn = 8, dn = 28 }))
GK.Hear(bert, "Hanne Moosgrund", Msg({ id = now - 4000, t = now - 4000 }))
GK.Hear(bert, "Hanne Moosgrund", Msg({ t = now - 10 }))
GK.Hear(bert, "Otto Fremd", Msg({ poster = "Otto Fremd" }))
check(rejected.activity == 1 and rejected.roles == 2 and rejected["too far ahead"] == 1 and rejected.expired == 1
  and rejected.version == 1 and rejected["not in guild"] == 1,
  "unknown activity, more filled than needed, nothing needed, a raid 9 days ahead, expired, version before id, a stranger")
check(Counts(PostOf(bert, "Hanne Moosgrund")) == Counts(before) and PostOf(bert, "Otto Fremd") == nil,
  "none of them changed what Bert holds")

section("The same version heard twice: counts only grow")
sched:advance(5)
local id = bert.RQ:Now()
GK.Hear(bert, "Cora Vale", Msg({ id = id, t = id, dh = 1 }))
GK.Hear(bert, "Dora Dunn", Msg({ id = id, t = id, dh = 2 }))
check(Counts(PostOf(bert, "Hanne Moosgrund")) == "0/1 0/1 2/3", "a relay that knows one more sign-up raises the count")
GK.Hear(bert, "Cora Vale", Msg({ id = id, t = id, dh = 1 }))
check(Counts(PostOf(bert, "Hanne Moosgrund")) == "0/1 0/1 2/3", "an older copy of the same version does not lower it")
NoErrors(cs)

Kit.finish()
