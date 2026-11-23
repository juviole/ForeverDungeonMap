local ADDON, ns = ...

local ready = false

local function showMap(mapID)
	ns.settingMap = true
	WorldMapFrame:SetMapID(mapID)
	ns.settingMap = false
end

function ns.OpenMap(mapID)
	if not WorldMapFrame then return end
	if not WorldMapFrame:IsShown() then
		ns.skipAutoOpen = true
		ToggleWorldMap()
		ns.skipAutoOpen = false
	end
	showMap(mapID)
end

-- Switch the open map to the dungeon (and floor) the player is in, unless the
-- map already shows a floor of it, so the player can still browse other floors.
local function syncToDungeon(followFloor)
	if not WorldMapFrame:IsShown() then return end
	local target = ns.ResolveCurrent()
	if not target then return end
	local current = WorldMapFrame:GetMapID()
	if not ns.SameDungeon(current, target) or (followFloor and current ~= target) then
		showMap(target)
	end
end

local function onClick(canvas, button)
	if not IsControlKeyDown() or (button ~= "LeftButton" and button ~= "RightButton") then
		return false
	end
	local mapID = canvas:GetMapID()
	if not ns.IsDungeonMap(mapID) then return false end
	if not ns.IsCurrentDungeon(mapID) then
		ns.Print("You can only mark rooms of the dungeon you are in.")
		return true
	end
	if button == "RightButton" then
		ns.ForgetRoom(mapID)
	else
		ns.MarkRoom(mapID, canvas:GetNormalizedCursorPosition())
	end
	return true
end

local function init()
	if ready or not WorldMapFrame then return end
	ready = true

	WorldMapFrame:AddDataProvider(ns.Provider)
	ns.CreatePanel(WorldMapFrame.ScrollContainer or WorldMapFrame)

	if WorldMapFrame.AddCanvasClickHandler then
		WorldMapFrame:AddCanvasClickHandler(onClick, 100)
	end

	WorldMapFrame:HookScript("OnShow", function()
		if ns.skipAutoOpen or not ns.db or not ns.db.autoOpen then return end
		-- The map picks its own zone while showing; switch after it is done.
		C_Timer.After(0, function() syncToDungeon(false) end)
	end)

	local lastRoom
	ns.OnRefresh(function()
		local room = ns.CurrentRoom()
		local roomChanged = room ~= lastRoom
		lastRoom = room
		if not WorldMapFrame:IsShown() then return end
		if roomChanged and ns.db.autoOpen and ns.IsCurrentDungeon(WorldMapFrame:GetMapID()) then
			syncToDungeon(true)
		end
		ns.Provider:RefreshAllData()
		ns.UpdatePanel()
	end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" and name ~= ADDON then return end
	init()
	if ready then self:UnregisterAllEvents() end
end)
