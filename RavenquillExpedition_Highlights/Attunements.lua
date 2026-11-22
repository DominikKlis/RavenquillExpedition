local ADDON, ns = ...
local H = ns.H

H.ATTUNEMENTS = {
  { raid = "mc", steps = { { quest = 7848, label = "STEP_CORE_FRAGMENT" } } },
  { raid = "ony", faction = "Alliance", steps = { { quest = 4322, label = "STEP_WINDSOR" },
    { quest = 6403, label = "STEP_MASQUERADE" }, { quest = 6502, label = "STEP_AMULET" } } },
  { raid = "ony", faction = "Horde", steps = { { quest = 4974, label = "STEP_REND" },
    { quest = 6601, label = "STEP_SKULLS" }, { quest = 6602, label = "STEP_BLOOD" } } },
  { raid = "bwl", steps = { { quest = 4743, label = "STEP_SEAL" }, { quest = 7761, label = "STEP_ORB" } } },
}

H.RAID_KEYS, H.ATTUNEMENT_QUESTS = {}, {}
local RAID = {}
for _, a in ipairs(H.ATTUNEMENTS) do
  if not RAID[a.raid] then H.RAID_KEYS[#H.RAID_KEYS + 1] = a.raid end
  RAID[a.raid] = true
  for _, step in ipairs(a.steps) do H.ATTUNEMENT_QUESTS[step.quest] = true end
end
