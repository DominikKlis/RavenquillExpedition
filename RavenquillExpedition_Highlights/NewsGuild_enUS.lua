local ADDON, ns = ...
local K = ns.NewsLocales.enUS.KINDS
ns.NewsLocales.enUS.RAIDS = { mc = "Molten Core", ony = "Onyxia's Lair", bwl = "Blackwing Lair" }

K.group = {
  kicker = { "Guild group", "Out together", "{?night}Night shift" },
  head = { "{inst}: {names} out together", "{names} make it through {inst}", "Guild group in {inst}",
    "{?midnight}Midnight in {inst}", "{!inst}{names} head out together" },
  dek = { "{people} from the guild headed out together.", "At {time} the group was back outside.", "The scene: {inst}." },
  body = { "At {time} the group reported the run done. Those who set out together come back together.",
    "{people} from the guild shared the work. The guild book is silent on how the loot was split.",
    "{?night}{!sure}Everyone was back {night}. Sleep will probably come later." },
  detail = { "At {time} the group was back outside.", "The scene: {inst}.", "Along for the run: {names}." },
  more = { "The editors congratulate.", "Repair bills, as always, are a private matter.",
    "{!sure}The next guild group will probably not be long in coming." },
  caption = { "{inst}", "Guild group" },
  brief = { "{inst}: {names} out together.", "{names} make it through {inst}.", "Guild group: {names}." },
  again = { "{gap}, also a guild group in {inst}.", "{gap}, also a guild group." },
}

K.clear = {
  kicker = { "Raid", "Full clear", "{?night}Night shift" },
  head = { "{inst}: the guild clears it", "The guild clears {inst}", "{inst} cleared", "{?midnight}Midnight in {inst}: all done",
    "{!inst}The guild reports a full clear" },
  dek = { "No boss was left standing.", "{grp} from the guild were there.", "The last foe fell at {time}.", "The scene: {inst}." },
  body = { "The final boss fell at {time}. After that, there was nothing left to do.",
    "{grp} from the guild were on the roster. {name} sent the report.",
    "{?night}{!sure}The last foe fell {night}. Sleep will probably be short today." },
  detail = { "The last foe fell at {time}.", "{grp} from the guild were on the roster.", "The scene: {inst}." },
  more = { "The loot, as usual, is shared out after careful deliberation.", "Repair bills, as always, are a private matter.",
    "{!sure}Next week will probably bring the next one." },
  caption = { "{inst}", "Raid" },
  brief = { "{inst}: the guild clears the raid.", "{inst} cleared.", "A raid cleared." },
  again = { "{gap}, also a clear of {inst}.", "{gap}, also a full clear." },
}

K.ready = {
  kicker = { "Raid ready", "Attuned", "{?names}Reinforcements for the raid" },
  head = { "{name} is ready for {raid}", "{names} are ready for {raid}", "{raid}: {name} is attuned", "{raid}: {names} are attuned",
    "{!raid}{name} is raid ready", "{!raid}{names} are raid ready" },
  dek = { "The last step of the attunement is done.", "At {time} it was done.", "{name} was level {clvl} at the time." },
  body = { "At {time} the guild book noted the last step. The way into the raid is open.",
    "The attunement is done. From now on the guild raid has one more seat to fill.",
    "{?night}The last step came {night}. Attunements, it seems, keep no closing time." },
  detail = { "At {time} it was done.", "{name} was level {clvl} at the time." },
  more = { "The editors congratulate.", "{!sure}The raid leaders will probably be pleased.",
    "Whoever still needs a step can see it under Raid readiness." },
  caption = { "{raid}", "Raid ready" },
  brief = { "{name} is ready for {raid}.", "{names} are ready for {raid}.", "{name} is raid ready.", "{names} are raid ready." },
  again = { "{gap}, also ready for {raid}.", "{gap}, also raid ready." },
}

K.first = {
  kicker = { "A first for the guild", "Never before", "{?lvl}Ahead of everyone" },
  head = { "{?lvl}A first for the guild: {name} reaches level {lvl}", "{?lvl}Ahead of everyone: {name} at level {lvl}",
    "{?boss}A first for the guild: {boss} defeated", "{?boss}{boss} falls for the first time",
    "{?boss}{inst}: {boss} falls for the first time", "{!lvl}{!boss}A first for the guild" },
  dek = { "{?lvl}Nobody in the guild had come this far before.", "{?boss}The guild had never beaten this foe before.",
    "At {time} it was done.", "{grp} from the guild were there." },
  body = { "{?lvl}At {time} the guild book noted level {lvl}. Nobody from the guild had ever come this far.",
    "{?boss}{boss} fell at {time}. A victory the guild had never had before.",
    "At {time} it was done. A day the guild will remember.",
    "{?night}The first came {night}. History, it seems, keeps no closing time." },
  detail = { "At {time} it was done.", "{grp} from the guild were on the roster.", "The scene: {inst}." },
  more = { "The editors congratulate and take a bow.", "{!sure}The others will probably follow soon.",
    "The guild book has a new first page." },
  caption = { "A first for the guild", "{?lvl}Level {lvl}", "{boss}" },
  brief = { "{?lvl}A first for the guild: {name} reaches level {lvl}.", "{?boss}A first for the guild: {boss} defeated.",
    "A first for the guild." },
  again = { "{?lvl}{gap}, a first: level {lvl}.", "{gap}, a first for the guild." },
}
