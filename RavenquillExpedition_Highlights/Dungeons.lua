local ADDON, ns = ...
local H = ns.H

H.DUNGEONS = {
  { "Ragefire Chasm", "Ragefireabgrund" },
  { "Deadmines", "Todesminen" },
  { "Wailing Caverns", "Höhlen des Wehklagens" },
  { "Shadowfang Keep", "Burg Shadowfang" },
  { "Blackfathom Deeps", "Blackfathom-Tiefe" },
  { "Stormwind Stockade", "Verlies von Stormwind" },
  { "Razorfen Kraul", "Kral von Razorfen" },
  { "Scarlet Monastery", "Scharlachrotes Kloster" },
  { "Razorfen Downs", "Hügel von Razorfen" },
  { "Sunken Temple", "Versunkener Tempel" },
  { "Blackrock Depths", "Blackrocktiefen" },
  { "Blackrock Spire", "Blackrockspitze" },
  { "Dire Maul", "Düsterbruch" },
  { "Caverns of Time", "Höhlen der Zeit" },
  { "The Searing Basin", "Das Sengende Becken" },
  { "Demon Fall Canyon", "Demonfall-Canyon" },
  { "Shadow Hold", "Schattenfeste" },
  { "Burning of Andorhal", "Brand von Andorhal" },
  { "Starfall Barrow Den", "Grabhügel von Starfall" },
  { "Deadwind Pass", "Gebirgspass der Totenwinde" },
  { "Karazhan Crypts", "Karazhangruften" },
  { "The Scarab Dais", "Die Skarabäushöhe" },
  { "City of Dalaran", "Dalaran" },
  { "Excavation Site: Wetlands", "Ausgrabungsstätte: Sumpfland" },
  { "Ruins of Lordaeron", "Ruinen von Lordaeron" },
  { "The Hall of Thanes", "Die Halle der Thanen" },
  { "Manor Mistmantle", "Anwesen der Mistmantles" },
  { "The Drowned City", "Die Versunkene Stadt" },
  { "Krol'dok Stronghold", "Feste Krol'dok" },
  { "Alcaz Prison", "Gefängnis von Alcaz" },
}

local dungeonKey = {}
for _, names in ipairs(H.DUNGEONS) do
  for _, name in ipairs(names) do dungeonKey[name] = names[1] end
end

function H.SameDungeon(a, b) return (dungeonKey[a] or a) == (dungeonKey[b] or b) end
