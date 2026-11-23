local _, ns = ...

local BOSS_TEMPLATE = "ForeverDungeonMapBossPinTemplate"
local YOU_TEMPLATE = "ForeverDungeonMapYouPinTemplate"

-- Boss pin --------------------------------------------------------------------

ForeverDungeonMapBossPinMixin = CreateFromMixins(MapCanvasPinMixin)

function ForeverDungeonMapBossPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_ENCOUNTER")
	self:SetScalingLimits(1, 1.0, 1.3)
end

function ForeverDungeonMapBossPinMixin:OnAcquired(boss)
	self.boss = boss
	self:SetPosition(boss.x, boss.y)
	self.Number:SetText(boss.index)
	self.Icon:SetDesaturated(boss.killed)
	self.Icon:SetAlpha(boss.killed and 0.6 or 1)
	self.Check:SetShown(boss.killed)
end

function ForeverDungeonMapBossPinMixin:OnMouseEnter()
	local boss = self.boss
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(("%d. %s"):format(boss.index, boss.name), 1, 0.82, 0)
	if boss.killed then
		GameTooltip:AddLine("Defeated", 0.5, 0.5, 0.5)
	end
	if boss.learned then
		GameTooltip:AddLine("Spot learned from the room you killed it in.", 0.7, 0.7, 0.7, true)
	end
	if boss.journalID and EncounterJournal_OpenJournal then
		GameTooltip:AddLine("Click to open the Adventure Guide.", 0.4, 0.8, 1)
	end
	GameTooltip:Show()
end

function ForeverDungeonMapBossPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

function ForeverDungeonMapBossPinMixin:OnMouseUp(button)
	ns.OpenJournal(self.boss)
end

-- "You" pin -------------------------------------------------------------------

ForeverDungeonMapYouPinMixin = CreateFromMixins(MapCanvasPinMixin)

function ForeverDungeonMapYouPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_GROUP_MEMBER")
	self:SetScalingLimits(1, 1.0, 1.3)
end

function ForeverDungeonMapYouPinMixin:OnAcquired(x, y, room)
	self.room = room
	self:SetPosition(x, y)
	self.Pulse:Play()
end

function ForeverDungeonMapYouPinMixin:OnReleased()
	self.Pulse:Stop()
end

function ForeverDungeonMapYouPinMixin:OnMouseEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("You are here", 1, 0.82, 0)
	GameTooltip:AddLine(self.room or "", 1, 1, 1)
	GameTooltip:AddLine("Placed by room. The game does not tell addons your exact position inside dungeons.", 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

function ForeverDungeonMapYouPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

-- Data provider ---------------------------------------------------------------

local Provider = CreateFromMixins(MapCanvasDataProviderMixin)
ns.Provider = Provider

local function nativeBossPinsShown(map)
	local ok, shown = pcall(function()
		for _ in map:EnumeratePinsByTemplate("EncounterJournalPinTemplate") do
			return true
		end
		return false
	end)
	return ok and shown
end

function Provider:RemoveAllData()
	self.generation = (self.generation or 0) + 1
	local map = self:GetMap()
	map:RemoveAllPinsByTemplate(BOSS_TEMPLATE)
	map:RemoveAllPinsByTemplate(YOU_TEMPLATE)
end

function Provider:RefreshAllData()
	self:RemoveAllData()
	local map = self:GetMap()
	local mapID = map:GetMapID()
	if not ns.db or not ns.IsDungeonMap(mapID) then return end

	if ns.IsCurrentDungeon(mapID) then
		local spot, room = ns.GetRoomSpot(mapID)
		if spot then
			map:AcquirePin(YOU_TEMPLATE, spot.x, spot.y, room)
		end
	end

	if not ns.db.bossPins then return end
	local bosses = ns.GetBosses(mapID)
	local generation = self.generation
	-- The game's own boss pins are added by another provider in the same pass,
	-- so wait a frame before deciding whether ours would duplicate them.
	C_Timer.After(0, function()
		if self.generation ~= generation or map:GetMapID() ~= mapID then return end
		local native = nativeBossPinsShown(map)
		for _, boss in ipairs(bosses) do
			if boss.x and not (native and boss.fromJournal) then
				map:AcquirePin(BOSS_TEMPLATE, boss)
			end
		end
	end)
end

function Provider:OnMapChanged()
	if not ns.settingMap then
		ns.RememberFloor(self:GetMap():GetMapID())
	end
	self:RefreshAllData()
	ns.UpdatePanel()
end

function ns.OpenJournal(boss)
	if not boss or not boss.journalID then return end
	if not EncounterJournal_OpenJournal and C_AddOns and C_AddOns.LoadAddOn then
		C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
	end
	if EncounterJournal_OpenJournal then
		local journalInstanceID = EJ_GetInstanceForMap and EJ_GetInstanceForMap(WorldMapFrame:GetMapID())
		pcall(EncounterJournal_OpenJournal, nil, journalInstanceID, boss.journalID)
	end
end
