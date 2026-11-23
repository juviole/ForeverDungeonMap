local ADDON, ns = ...

local PREFIX = "|cff66bbffDungeon Map:|r "
local RUN_EXPIRY = 60 * 60

local DEFAULTS = {
	autoOpen = true,
	mode = "live",
	rooms = {},
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

-- Where the player is ------------------------------------------------------------

function ns.CurrentInstance()
	local inInstance, instanceType = IsInInstance()
	if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then return nil end
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	name, instanceID = ns.Safe(name), ns.Safe(instanceID)
	if not instanceID then return nil end
	return { name = name, instanceID = instanceID, type = instanceType }
end

function ns.CurrentDungeon()
	return ns.FindDungeon(ns.CurrentInstance())
end

function ns.CurrentRoom()
	for _, text in ipairs({ GetSubZoneText(), GetMinimapZoneText() }) do
		text = ns.Safe(text)
		local key = normalize(text)
		if key then return key, text end
	end
end

-- Floors and rooms ------------------------------------------------------------------

local function roomKey(dungeonID, floor)
	return dungeonID .. ":" .. floor
end

-- The floor to show for the dungeon the player is in.
function ns.PickFloor(dungeonID)
	local floors = ns.GetFloors(dungeonID)
	if #floors <= 1 then return 1 end
	local room = ns.CurrentRoom()
	if room then
		for i, floor in ipairs(floors) do
			if normalize(floor.name) == room then return i end
		end
		for i = 1, #floors do
			local rooms = db.rooms[roomKey(dungeonID, i)]
			if rooms and rooms[room] then return i end
		end
		local learned = db.floors[dungeonID] and db.floors[dungeonID][room]
		if learned and floors[learned] then return learned end
	end
	local inst = ns.CurrentInstance()
	local instName = inst and normalize(inst.name)
	if instName then
		for i, floor in ipairs(floors) do
			local n = normalize(floor.name)
			if n and i > 1 and instName:find(n, 1, true) then return i end
		end
	end
	local last = db.lastFloor[dungeonID]
	if last and floors[last] then return last end
	return 1
end

-- True when the floor for the current room is known, so the map may follow it.
function ns.FloorForRoomKnown(dungeonID)
	local room = ns.CurrentRoom()
	if not room then return false end
	for i, floor in ipairs(ns.GetFloors(dungeonID)) do
		if normalize(floor.name) == room then return true end
		local rooms = db.rooms[roomKey(dungeonID, i)]
		if rooms and rooms[room] then return true end
	end
	return db.floors[dungeonID] ~= nil and db.floors[dungeonID][room] ~= nil
end

function ns.RememberFloor(dungeonID, floor)
	if ns.CurrentDungeon() ~= dungeonID then return end
	db.lastFloor[dungeonID] = floor
	local room = ns.CurrentRoom()
	if room then
		subTable(db.floors, dungeonID)[room] = floor
	end
end

function ns.MarkRoom(dungeonID, floor, x, y)
	local key, label = ns.CurrentRoom()
	if not key then
		ns.Print("This spot has no room name, so there is nothing to mark.")
		return
	end
	subTable(db.rooms, roomKey(dungeonID, floor))[key] = { x = x, y = y, name = label }
	ns.RememberFloor(dungeonID, floor)
	ns.Print(("Marked %s. Your dot appears there whenever you are in it."):format(label))
	ns.Refresh()
end

function ns.ForgetRoom(dungeonID, floor)
	local key, label = ns.CurrentRoom()
	local rooms = db.rooms[roomKey(dungeonID, floor)]
	if key and rooms and rooms[key] then
		rooms[key] = nil
		ns.Print(("Forgot the spot for %s."):format(label))
		ns.Refresh()
	end
end

function ns.ForgetAllRooms(dungeonID)
	for i = 1, math.max(1, #ns.GetFloors(dungeonID)) do
		db.rooms[roomKey(dungeonID, i)] = nil
	end
	db.floors[dungeonID] = nil
	ns.Refresh()
end

function ns.GetRoomSpot(dungeonID, floor)
	local key, label = ns.CurrentRoom()
	local rooms = db.rooms[roomKey(dungeonID, floor)]
	if key and rooms and rooms[key] then
		return rooms[key], label
	end
	return nil, label
end

-- Bosses --------------------------------------------------------------------------

local function currentRun()
	local inst = ns.CurrentInstance()
	if not inst then return nil end
	local run = db.run
	local now = time()
	if not run or run.instanceID ~= inst.instanceID or now - (run.lastSeen or 0) > RUN_EXPIRY then
		run = { instanceID = inst.instanceID, kills = {}, order = {} }
		db.run = run
	end
	run.lastSeen = now
	return run
end

local function markKilled(name)
	local run = currentRun()
	local key = normalize(name)
	if not run or not key or run.kills[key] then return end
	run.kills[key] = true
	run.order[#run.order + 1] = name
end

local function lockoutBosses()
	local list = {}
	if not GetInstanceLockTimeRemaining or not ns.CurrentInstance() then return list end
	local _, _, total = GetInstanceLockTimeRemaining()
	for i = 1, ns.Safe(total) or 0 do
		local name, _, isKilled = GetInstanceLockTimeRemainingEncounter(i)
		name = ns.Safe(name)
		if name then
			list[#list + 1] = { name = name, killed = ns.Safe(isKilled) and true or false }
		end
	end
	return list
end

-- Bosses of the run in the dungeon the player is in: the lockout's list when the
-- game gives one, then every boss killed this run that it lacks.
function ns.GetBosses()
	local bosses, seen = {}, {}
	local run = db.run
	local inst = ns.CurrentInstance()
	local kills = (run and inst and run.instanceID == inst.instanceID) and run.kills or {}
	for _, boss in ipairs(lockoutBosses()) do
		local key = normalize(boss.name)
		boss.killed = boss.killed or kills[key] == true
		bosses[#bosses + 1] = boss
		seen[key] = true
	end
	if run and kills == run.kills then
		for _, name in ipairs(run.order) do
			if not seen[normalize(name)] then
				bosses[#bosses + 1] = { name = name, killed = true }
			end
		end
	end
	return bosses
end

-- Refresh ---------------------------------------------------------------------------

local refreshCallbacks = {}

function ns.OnRefresh(fn)
	refreshCallbacks[#refreshCallbacks + 1] = fn
end

function ns.Refresh()
	for _, fn in ipairs(refreshCallbacks) do fn() end
end

-- Events ------------------------------------------------------------------------------

local resetPattern
if INSTANCE_RESET_SUCCESS then
	local escaped = INSTANCE_RESET_SUCCESS:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	resetPattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

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
	-- Saved data from 1.0, which keyed everything by map IDs this client lacks.
	if not db.version or db.version < 2 then
		db.rooms, db.floors, db.lastFloor, db.run = {}, {}, {}, nil
		db.bindings, db.bossSpots, db.bossPins, db.panel = nil, nil, nil, nil
		db.version = 2
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
	ns.Refresh()
end

function handlers.ENCOUNTER_END(_, name, _, _, success)
	if ns.Safe(success) ~= 1 then return end
	markKilled(ns.Safe(name))
	ns.Refresh()
end

function handlers.BOSS_KILL(_, name)
	markKilled(ns.Safe(name))
	ns.Refresh()
end

function handlers.CHAT_MSG_SYSTEM(msg)
	msg = ns.Safe(msg)
	if resetPattern and type(msg) == "string" and msg:match(resetPattern) then
		db.run = nil
		ns.Refresh()
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
for event in pairs(handlers) do
	events:RegisterEvent(event)
end

-- Slash commands ----------------------------------------------------------------------

local HELP = {
	"Press M inside a dungeon to open the dungeon map.",
	"/dmap - open or close the dungeon map window anywhere",
	"/dmap show <name> - look at any dungeon's map",
	"/dmap list - list the dungeons with a map",
	"/dmap live - switch to the live view (your minimap, with your arrow)",
	"/dmap map - switch to the dungeon's full map",
	"/dmap auto - turn opening this on M inside dungeons on or off",
	"/dmap reset - clear the defeated bosses of this run",
	"/dmap forget - forget the rooms marked for the dungeon shown",
	"/dmap debug - show what the addon sees",
	"On the full map: Ctrl+Left-click marks the room you are in, Ctrl+Right-click forgets it.",
}

local commands = {}

function commands.show(arg)
	local id = arg and ns.SearchDungeon(arg)
	if not id then
		ns.Print("No dungeon found for '" .. tostring(arg) .. "'. Try /dmap list.")
		return
	end
	ns.ShowWindow(id, "map")
end

function commands.list()
	for _, entry in ipairs(ns.SortedDungeons()) do
		local floors = #ns.GetFloors(entry.id)
		ns.Print(("%s - %s"):format(entry.name, floors > 0 and (floors .. (floors == 1 and " map" or " maps")) or "|cffff6060no map art found|r"))
	end
end

function commands.live()
	db.mode = "live"
	ns.Refresh()
end

commands.map = function()
	db.mode = "map"
	ns.Refresh()
end
commands.art = commands.map

function commands.auto()
	db.autoOpen = not db.autoOpen
	ns.Print("Open the dungeon map on M inside dungeons: " .. (db.autoOpen and "on" or "off"))
end

function commands.reset()
	db.run = nil
	ns.Print("Defeated bosses cleared.")
	ns.Refresh()
end

function commands.forget()
	local id = ns.ShownDungeon and ns.ShownDungeon()
	if id then
		ns.ForgetAllRooms(id)
		ns.Print("Forgot the rooms marked for " .. ns.Dungeons[id].name .. ".")
	else
		ns.Print("Open a dungeon's map first.")
	end
end

function commands.debug()
	local inst = ns.CurrentInstance()
	local id = ns.FindDungeon(inst)
	local _, room = ns.CurrentRoom()
	ns.Print("Client interface:", select(4, GetBuildInfo()))
	ns.Print("Instance:", inst and (tostring(inst.name) .. " (ID " .. inst.instanceID .. ", " .. inst.type .. ")") or "not in a dungeon or raid")
	ns.Print("Dungeon:", id and ns.Dungeons[id].name or "not in the addon's list")
	if id then
		local floors = ns.GetFloors(id)
		ns.Print("Map art:", #floors > 0 and (#floors .. " floor(s), " .. floors[1].prefix .. "1") or "none found")
	end
	ns.Print("Room:", tostring(room))
	ns.Print("GetFileIDFromPath:", GetFileIDFromPath and "yes" or "missing")
	if Minimap then
		local function frameName(f)
			if type(f) ~= "table" then return tostring(f) end
			return f.GetName and f:GetName() or "unnamed"
		end
		local point, relativeTo = Minimap:GetPoint(1)
		ns.Print(("Minimap: parent %s, anchored %s to %s, size %d, times put back %d"):format(
			frameName(Minimap:GetParent()), tostring(point), frameName(relativeTo),
			Minimap:GetWidth() or 0, ns.minimapMoves or 0))
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
		ns.ToggleWindow()
	elseif commands[cmd] then
		commands[cmd](arg ~= "" and arg or nil)
	else
		commands.help()
	end
end
