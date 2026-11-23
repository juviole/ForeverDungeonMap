local _, ns = ...

-- Classic instance map IDs and the folders of their map art under
-- Interface\WorldMap. Some folders have more than one spelling across builds,
-- so every candidate is probed and the first one found is used.
ns.Dungeons = {
	[389] = { name = "Ragefire Chasm", art = { "Ragefire" } },
	[43] = { name = "Wailing Caverns", art = { "WailingCaverns" } },
	[36] = { name = "The Deadmines", art = { "TheDeadmines" }, floorNames = { "The Deadmines", "Ironclad Cove" } },
	[33] = { name = "Shadowfang Keep", art = { "ShadowfangKeep" } },
	[34] = { name = "The Stockade", art = { "TheStockade" } },
	[48] = { name = "Blackfathom Deeps", art = { "BlackFathomDeeps", "BlackfathomDeeps" } },
	[90] = { name = "Gnomeregan", art = { "Gnomeregan" } },
	[47] = { name = "Razorfen Kraul", art = { "RazorfenKraul" } },
	[189] = { name = "Scarlet Monastery", art = { "ScarletMonastery" }, floorNames = { "Graveyard", "Library", "Armory", "Cathedral" } },
	[129] = { name = "Razorfen Downs", art = { "RazorfenDowns" } },
	[70] = { name = "Uldaman", art = { "Uldaman" } },
	[209] = { name = "Zul'Farrak", art = { "ZulFarrak" } },
	[349] = { name = "Maraudon", art = { "Maraudon" } },
	[109] = { name = "Sunken Temple", art = { "TheTempleOfAtalHakkar", "TempleOfAtalHakkar", "SunkenTemple" } },
	[230] = { name = "Blackrock Depths", art = { "BlackrockDepths" } },
	[229] = { name = "Blackrock Spire", art = { "BlackrockSpire" } },
	[429] = { name = "Dire Maul", art = { "DireMaul" } },
	[289] = { name = "Scholomance", art = { "Scholomance", "ScholomanceOLD" } },
	[329] = { name = "Stratholme", art = { "Stratholme" } },
	[409] = { name = "Molten Core", art = { "MoltenCore" } },
	[249] = { name = "Onyxia's Lair", art = { "OnyxiasLair" } },
	[469] = { name = "Blackwing Lair", art = { "BlackwingLair" } },
	[309] = { name = "Zul'Gurub", art = { "ZulGurub" } },
	[509] = { name = "Ruins of Ahn'Qiraj", art = { "RuinsofAhnQiraj" } },
	[531] = { name = "Temple of Ahn'Qiraj", art = { "AhnQiraj", "TempleofAhnQiraj" } },
	[533] = { name = "Naxxramas", art = { "Naxxramas" } },
}

ns.ART_WIDTH, ns.ART_HEIGHT = 1002, 668
ns.TILE_SIZE = 256

local MAX_FLOORS = 12

local function fileExists(path)
	if not GetFileIDFromPath then return nil end
	local ok, id = pcall(GetFileIDFromPath, path)
	if not ok then return nil end
	return id ~= nil and id ~= 0
end

-- Each floor is a prefix; tile n (1..12) is prefix .. n, in a 4 by 3 grid.
local function probe(dungeon)
	local canProbe = GetFileIDFromPath ~= nil
	for _, folder in ipairs(dungeon.art) do
		local base = "Interface\\WorldMap\\" .. folder .. "\\" .. folder
		local floors = {}
		for floor = 1, MAX_FLOORS do
			local prefix = base .. floor .. "_"
			if fileExists(prefix .. "1") then
				floors[#floors + 1] = { prefix = prefix }
			elseif #floors > 0 then
				break
			end
		end
		if #floors == 0 and fileExists(base .. "1") then
			floors[1] = { prefix = base }
		end
		if #floors > 0 then return floors end
	end
	if not canProbe then
		return { { prefix = "Interface\\WorldMap\\" .. dungeon.art[1] .. "\\" .. dungeon.art[1] .. "1_" } }
	end
	return {}
end

function ns.GetFloors(dungeonID)
	local dungeon = ns.Dungeons[dungeonID]
	if not dungeon then return {} end
	if not dungeon.floors then
		dungeon.floors = probe(dungeon)
		for i, floor in ipairs(dungeon.floors) do
			floor.name = dungeon.floorNames and dungeon.floorNames[i] or ("Level " .. i)
		end
	end
	return dungeon.floors
end

-- The dungeon the player is in, by instance ID, then by name.
function ns.FindDungeon(inst)
	if not inst then return nil end
	if ns.Dungeons[inst.instanceID] then return inst.instanceID end
	local key = ns.Normalize(inst.name)
	if not key then return nil end
	for id, dungeon in pairs(ns.Dungeons) do
		local dkey = ns.Normalize(dungeon.name)
		if key == dkey or key:find(dkey, 1, true) then return id end
	end
end

function ns.SearchDungeon(text)
	local id = tonumber(text)
	if id and ns.Dungeons[id] then return id end
	local key = ns.Normalize(text)
	if not key then return nil end
	for dungeonID, dungeon in pairs(ns.Dungeons) do
		if ns.Normalize(dungeon.name):find(key, 1, true) then return dungeonID end
	end
end

function ns.SortedDungeons()
	local list = {}
	for id, dungeon in pairs(ns.Dungeons) do
		list[#list + 1] = { id = id, name = dungeon.name }
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end
