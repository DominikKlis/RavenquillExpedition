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
