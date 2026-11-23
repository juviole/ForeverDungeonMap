local ADDON, ns = ...

local PREFIX = "|cff66bbffDungeon Map:|r "
local MAX_MAP_ID = 5000
local RUN_EXPIRY = 60 * 60

local DEFAULTS = {
	autoOpen = true,
	bossPins = true,
	panel = true,
	bindings = {},
	rooms = {},
	bossSpots = {},
	floors = {},
	lastFloor = {},
}

local db

function ns.Print(...)
	print(PREFIX .. string.join(" ", tostringall(...)))
end

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

function ns.Safe(v)
	if isSecret(v) then return nil end
	return v
end

function ns.Normalize(s)
	if type(s) ~= "string" or isSecret(s) then return nil end
	s = s:lower():gsub("^the%s+", ""):gsub("[%s%p]", "")
	if s == "" then return nil end
	return s
end
local normalize = ns.Normalize

local function subTable(t, key)
	local v = t[key]
	if not v then
		v = {}
		t[key] = v
	end
	return v
end
ns.SubTable = subTable

-- Map catalogue ---------------------------------------------------------------

local DUNGEON = Enum.UIMapType.Dungeon
local MICRO = Enum.UIMapType.Micro

local index

function ns.IsDungeonMap(mapID)
	if not mapID then return false end
	local info = C_Map.GetMapInfo(mapID)
	return info ~= nil and (info.mapType == DUNGEON or info.mapType == MICRO)
end

function ns.GetIndex()
	if index then return index end
	index = { byName = {}, list = {} }
	local seenGroups = {}
	for mapID = 1, MAX_MAP_ID do
		local info = C_Map.GetMapInfo(mapID)
		if info and (info.mapType == DUNGEON or info.mapType == MICRO) then
			local groupID = C_Map.GetMapGroupID(mapID)
			if not groupID or not seenGroups[groupID] then
				if groupID then seenGroups[groupID] = true end
				local entry = { mapID = mapID, name = info.name, mapType = info.mapType, groupID = groupID }
				index.list[#index.list + 1] = entry
				local key = normalize(info.name)
				if key then
					local bucket = subTable(index.byName, key)
					bucket[#bucket + 1] = entry
				end
			end
		end
	end
	table.sort(index.list, function(a, b)
		if a.mapType ~= b.mapType then return a.mapType == DUNGEON end
		return a.name < b.name
	end)
	return index
end

function ns.GetFloors(mapID)
	local groupID = C_Map.GetMapGroupID(mapID)
	if groupID then
		local members = C_Map.GetMapGroupMembersInfo(groupID)
		if members and #members > 0 then
			return members, groupID
		end
	end
	local info = C_Map.GetMapInfo(mapID)
	return { { mapID = mapID, name = info and info.name or tostring(mapID) } }, nil
end

function ns.SameDungeon(a, b)
	if not a or not b then return false end
	if a == b then return true end
	local ga = C_Map.GetMapGroupID(a)
	return ga ~= nil and ga == C_Map.GetMapGroupID(b)
end

local function floorsContain(floors, mapID)
	for _, f in ipairs(floors) do
		if f.mapID == mapID then return true end
	end
	return false
end

-- Current instance ------------------------------------------------------------

function ns.CurrentInstance()
	local inInstance, instanceType = IsInInstance()
	if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then return nil end
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	name, instanceID = ns.Safe(name), ns.Safe(instanceID)
	if not instanceID then return nil end
	return { name = name, instanceID = instanceID, key = tostring(instanceID), type = instanceType }
end

function ns.CurrentRoom()
	for _, text in ipairs({ GetSubZoneText(), GetMinimapZoneText() }) do
		text = ns.Safe(text)
		local key = normalize(text)
		if key then return key, text end
	end
end

-- Returns the dungeon map for the instance the player is in, and how it was found.
local function resolveBase(inst)
	local bound = db.bindings[inst.key]
	if bound and C_Map.GetMapInfo(bound) then
		return bound, "bound with /dmap bind"
	end

	local best = C_Map.GetBestMapForUnit("player")
	if best then
		local info = C_Map.GetMapInfo(best)
		if info and info.mapType == DUNGEON then
			return best, "reported by the game", true
		end
	end

	local idx = ns.GetIndex()
	for _, name in ipairs({ inst.name, ns.Safe(GetRealZoneText()), ns.Safe(GetZoneText()) }) do
		local bucket = idx.byName[normalize(name) or ""]
		if bucket then
			for _, entry in ipairs(bucket) do
				if entry.mapType == DUNGEON then return entry.mapID, "matched by name" end
			end
			return bucket[1].mapID, "matched by name"
		end
	end
end

function ns.PickFloor(baseMapID, inst)
	local floors = ns.GetFloors(baseMapID)
	if #floors == 1 then return floors[1].mapID end

	local room = ns.CurrentRoom()
	if room then
		for _, f in ipairs(floors) do
			if normalize(f.name) == room then return f.mapID end
		end
		for _, f in ipairs(floors) do
			local rooms = db.rooms[f.mapID]
			if rooms and rooms[room] then return f.mapID end
		end
		local learned = db.floors[inst.key] and db.floors[inst.key][room]
		if learned and floorsContain(floors, learned) then return learned end
	end

	local last = db.lastFloor[inst.key]
	if last and floorsContain(floors, last) then return last end
	if floorsContain(floors, baseMapID) then return baseMapID end
	return floors[1].mapID
end

function ns.ResolveCurrent()
	local inst = ns.CurrentInstance()
	if not inst then return nil end
	local base, source, exactFloor = resolveBase(inst)
	if not base then return nil, nil, inst end
	if exactFloor then return base, source, inst end
	return ns.PickFloor(base, inst), source, inst
end

-- True when mapID is a floor of the dungeon the player is currently inside.
function ns.IsCurrentDungeon(mapID)
	local current = ns.ResolveCurrent()
	return current ~= nil and ns.SameDungeon(current, mapID)
end

function ns.RememberFloor(mapID)
	local inst = ns.CurrentInstance()
	if not inst or not ns.IsCurrentDungeon(mapID) then return end
	db.lastFloor[inst.key] = mapID
	local room = ns.CurrentRoom()
	if room then
		subTable(db.floors, inst.key)[room] = mapID
	end
end

-- Kill tracking ---------------------------------------------------------------

local function currentRun()
	local inst = ns.CurrentInstance()
	if not inst then return nil end
	local run = db.run
	local now = time()
	if not run or run.instanceID ~= inst.instanceID or now - (run.lastSeen or 0) > RUN_EXPIRY then
		run = { instanceID = inst.instanceID, kills = {} }
		db.run = run
	end
	run.lastSeen = now
	return run
end

local function markKilled(encounterID, name)
	local run = currentRun()
	if not run then return end
	if encounterID then run.kills["id:" .. encounterID] = true end
	local key = normalize(name)
	if key then run.kills[key] = true end
end

function ns.IsKilled(boss)
	local run = db.run
	local inst = ns.CurrentInstance()
	if not run or not inst or run.instanceID ~= inst.instanceID then return false end
	if boss.encounterID and run.kills["id:" .. boss.encounterID] then return true end
	local key = normalize(boss.name)
	return key ~= nil and run.kills[key] == true
end

local function readLockout()
	if not GetInstanceLockTimeRemaining or not ns.CurrentInstance() then return end
	local _, _, total = GetInstanceLockTimeRemaining()
	total = ns.Safe(total)
	if not total then return end
	for i = 1, total do
		local name, _, isKilled = GetInstanceLockTimeRemainingEncounter(i)
		if ns.Safe(isKilled) then markKilled(nil, ns.Safe(name)) end
	end
end

local function lockoutBossNames()
	local names = {}
	if not GetInstanceLockTimeRemaining or not ns.CurrentInstance() then return names end
	local _, _, total = GetInstanceLockTimeRemaining()
	total = ns.Safe(total)
	for i = 1, total or 0 do
		local name = ns.Safe((GetInstanceLockTimeRemainingEncounter(i)))
		if name then names[#names + 1] = name end
	end
	return names
end

-- Bosses ----------------------------------------------------------------------

-- Bosses of the dungeon shown on mapID. Each boss has a name and, when known,
-- a position (x, y) on this floor.
function ns.GetBosses(mapID)
	local bosses, byKey = {}, {}
	local function add(name, journalID, encounterID)
		local key = normalize(name)
		if not key or byKey[key] then return byKey[key] end
		local boss = { index = #bosses + 1, name = name, journalID = journalID, encounterID = encounterID }
		bosses[#bosses + 1] = boss
		byKey[key] = boss
		return boss
	end

	local journalInstanceID = EJ_GetInstanceForMap and EJ_GetInstanceForMap(mapID)
	if journalInstanceID and journalInstanceID > 0 and EJ_GetEncounterInfoByIndex then
		for i = 1, 50 do
			local name, _, journalID, _, _, _, encounterID = EJ_GetEncounterInfoByIndex(i, journalInstanceID)
			if not name then break end
			add(name, journalID, encounterID)
		end
	end

	if ns.IsCurrentDungeon(mapID) then
		for _, name in ipairs(lockoutBossNames()) do add(name) end
	end

	if C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap then
		for _, onMap in ipairs(C_EncounterJournal.GetEncountersOnMap(mapID) or {}) do
			for _, boss in ipairs(bosses) do
				if boss.journalID == onMap.encounterID then
					boss.x, boss.y, boss.fromJournal = onMap.mapX, onMap.mapY, true
				end
			end
		end
	end

	for key, spot in pairs(db.bossSpots[mapID] or {}) do
		local boss = byKey[key] or add(spot.name)
		if boss and not boss.x then
			boss.x, boss.y, boss.learned = spot.x, spot.y, true
		end
	end

	for _, boss in ipairs(bosses) do
		boss.killed = ns.IsKilled(boss)
	end
	return bosses
end

-- Rooms -----------------------------------------------------------------------

function ns.MarkRoom(mapID, x, y)
	local key, label = ns.CurrentRoom()
	if not key then
		ns.Print("This spot has no room name, so there is nothing to mark.")
		return
	end
	subTable(db.rooms, mapID)[key] = { x = x, y = y, name = label }
	ns.RememberFloor(mapID)
	ns.Print(("Marked %s here. Your marker will appear here whenever you are in it."):format(label))
	ns.Refresh()
end

function ns.ForgetRoom(mapID)
	local key, label = ns.CurrentRoom()
	local rooms = db.rooms[mapID]
	if key and rooms and rooms[key] then
		rooms[key] = nil
		ns.Print(("Forgot the spot for %s."):format(label))
		ns.Refresh()
	end
end

function ns.GetRoomSpot(mapID)
	local key, label = ns.CurrentRoom()
	local rooms = db.rooms[mapID]
	if key and rooms and rooms[key] then
		return rooms[key], label
	end
	return nil, label
end

local function learnBossSpot(name)
	local mapID = ns.ResolveCurrent()
	local key = normalize(name)
	if not mapID or not key then return end
	local spot = ns.GetRoomSpot(mapID)
	local spots = subTable(db.bossSpots, mapID)
	if spot and not spots[key] then
		spots[key] = { x = spot.x, y = spot.y, name = name }
	end
end

-- Refresh ---------------------------------------------------------------------

local refreshCallbacks = {}

function ns.OnRefresh(fn)
	refreshCallbacks[#refreshCallbacks + 1] = fn
end

function ns.Refresh()
	for _, fn in ipairs(refreshCallbacks) do fn() end
end

-- Events ----------------------------------------------------------------------

local resetPattern
if INSTANCE_RESET_SUCCESS then
	local escaped = INSTANCE_RESET_SUCCESS:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	resetPattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

local events = CreateFrame("Frame")

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON then return end
	ForeverDungeonMapDB = ForeverDungeonMapDB or {}
	db = ForeverDungeonMapDB
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then
			db[k] = type(v) == "table" and {} or v
		end
	end
	ns.db = db
end

function handlers.PLAYER_ENTERING_WORLD()
	if ns.CurrentInstance() then
		currentRun()
		if RequestRaidInfo then RequestRaidInfo() end
	end
	ns.Refresh()
end

function handlers.ZONE_CHANGED()
	if ns.CurrentInstance() then currentRun() end
	ns.Refresh()
end
handlers.ZONE_CHANGED_INDOORS = handlers.ZONE_CHANGED
handlers.ZONE_CHANGED_NEW_AREA = handlers.ZONE_CHANGED

function handlers.UPDATE_INSTANCE_INFO()
	readLockout()
	ns.Refresh()
end

function handlers.ENCOUNTER_END(encounterID, name, _, _, success)
	if ns.Safe(success) ~= 1 then return end
	name = ns.Safe(name)
	markKilled(ns.Safe(encounterID), name)
	learnBossSpot(name)
	ns.Refresh()
end

function handlers.BOSS_KILL(encounterID, name)
	name = ns.Safe(name)
	markKilled(ns.Safe(encounterID), name)
	learnBossSpot(name)
	ns.Refresh()
end

function handlers.CHAT_MSG_SYSTEM(msg)
	msg = ns.Safe(msg)
	if resetPattern and type(msg) == "string" and msg:match(resetPattern) then
		db.run = nil
		ns.Refresh()
	end
end

events:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
for event in pairs(handlers) do
	events:RegisterEvent(event)
end

-- Slash commands --------------------------------------------------------------

local function showList(filter)
	local key = normalize(filter)
	local shown = 0
	for _, entry in ipairs(ns.GetIndex().list) do
		local n = normalize(entry.name) or ""
		if (not key or n:find(key, 1, true)) and entry.mapType == DUNGEON then
			ns.Print(("%d  %s"):format(entry.mapID, entry.name))
			shown = shown + 1
			if shown >= 40 then
				ns.Print("...more. Narrow it down with /dmap list <name>.")
				break
			end
		end
	end
	if shown == 0 then ns.Print("No dungeon maps match that.") end
end

local function findMap(arg)
	local id = tonumber(arg)
	if id then return C_Map.GetMapInfo(id) and id end
	local key = normalize(arg)
	if not key then return nil end
	local idx = ns.GetIndex()
	local exact = idx.byName[key]
	if exact then return exact[1].mapID end
	for _, entry in ipairs(idx.list) do
		if (normalize(entry.name) or ""):find(key, 1, true) then return entry.mapID end
	end
end

local HELP = {
	"/dmap - open the map of the dungeon you are in",
	"/dmap show <name or map ID> - open any dungeon map",
	"/dmap list [name] - list dungeon maps",
	"/dmap bind - use the map shown now for this instance",
	"/dmap unbind - go back to finding this instance's map automatically",
	"/dmap auto - turn opening the dungeon map on M on or off",
	"/dmap panel - show or hide the boss list on the map",
	"/dmap pins - show or hide boss markers",
	"/dmap reset - clear the defeated bosses of this run",
	"/dmap forget - forget the rooms you marked on the map shown now",
	"/dmap debug - show what the addon sees",
	"On a dungeon map: Ctrl+Left-click marks the room you are in, Ctrl+Right-click forgets it.",
}

local commands = {}

function commands.show(arg)
	local mapID = findMap(arg)
	if not mapID then
		ns.Print("No map found for '" .. tostring(arg) .. "'. Try /dmap list.")
		return
	end
	ns.OpenMap(mapID)
end

function commands.list(arg)
	showList(arg)
end

function commands.bind()
	local inst = ns.CurrentInstance()
	local mapID = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
	if not inst then
		ns.Print("You need to be inside a dungeon.")
	elseif not mapID or not ns.IsDungeonMap(mapID) then
		ns.Print("Open the right dungeon map first (for example with /dmap show <name>), then type /dmap bind.")
	else
		db.bindings[inst.key] = mapID
		ns.Print(("%s now opens map %d (%s)."):format(inst.name or inst.key, mapID, C_Map.GetMapInfo(mapID).name))
		ns.Refresh()
	end
end

function commands.unbind()
	local inst = ns.CurrentInstance()
	if inst then
		db.bindings[inst.key] = nil
		ns.Print("This instance's map is found automatically again.")
		ns.Refresh()
	end
end

function commands.auto()
	db.autoOpen = not db.autoOpen
	ns.Print("Open the dungeon map on M: " .. (db.autoOpen and "on" or "off"))
end

function commands.panel()
	db.panel = not db.panel
	ns.Print("Boss list: " .. (db.panel and "shown" or "hidden"))
	ns.Refresh()
end

function commands.pins()
	db.bossPins = not db.bossPins
	ns.Print("Boss markers: " .. (db.bossPins and "shown" or "hidden"))
	ns.Refresh()
end

function commands.reset()
	db.run = nil
	ns.Print("Defeated bosses cleared.")
	ns.Refresh()
end

function commands.forget()
	local mapID = WorldMapFrame and WorldMapFrame:GetMapID()
	if mapID and db.rooms[mapID] then
		db.rooms[mapID] = nil
		db.bossSpots[mapID] = nil
		ns.Print("Forgot the rooms and boss spots marked on this map.")
		ns.Refresh()
	else
		ns.Print("Nothing marked on the map shown now.")
	end
end

function commands.debug()
	local inst = ns.CurrentInstance()
	local mapID, source = ns.ResolveCurrent()
	local _, room = ns.CurrentRoom()
	ns.Print("Instance:", inst and (tostring(inst.name) .. " (" .. inst.key .. ")") or "not in a dungeon")
	ns.Print("Game's map for you:", tostring(C_Map.GetBestMapForUnit("player")))
	ns.Print("Dungeon map:", mapID and (mapID .. " " .. C_Map.GetMapInfo(mapID).name .. ", " .. source) or "none found")
	ns.Print("Room:", tostring(room))
	ns.Print("Dungeon maps in this client:", #ns.GetIndex().list)
	if mapID then
		local bosses = ns.GetBosses(mapID)
		ns.Print("Bosses known:", #bosses)
	end
end

function commands.help()
	for _, line in ipairs(HELP) do ns.Print(line) end
end

SLASH_FOREVERDUNGEONMAP1 = "/dmap"
SLASH_FOREVERDUNGEONMAP2 = "/dungeonmap"
SlashCmdList.FOREVERDUNGEONMAP = function(msg)
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" then
		local mapID, _, inst = ns.ResolveCurrent()
		if mapID then
			ns.OpenMap(mapID)
		elseif inst then
			ns.Print("No map found for this instance. Open one with /dmap show <name>, then /dmap bind.")
		else
			ns.Print("You are not in a dungeon. /dmap help lists the commands.")
		end
	elseif commands[cmd] then
		commands[cmd](arg ~= "" and arg or nil)
	else
		commands.help()
	end
end
