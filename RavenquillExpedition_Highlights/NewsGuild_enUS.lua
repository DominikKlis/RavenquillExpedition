local ADDON, ns = ...
local K = ns.NewsLocales.enUS.KINDS

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
