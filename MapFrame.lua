local _, ns = ...

local HEADER = 32
local FOOTER = 24
local MARGIN = 6
local STANDALONE_SCALE = 0.8
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

local ART_W, ART_H, TILE = ns.ART_WIDTH, ns.ART_HEIGHT, ns.TILE_SIZE

local frame, content, canvas, tiles, youDot, title
local floorLabel, prevButton, nextButton, liveTab, mapTab, closeButton
local footerText, bossText, noArtText, liveHolder

local state = { dungeonID = nil, floor = 1, docked = false, room = nil }

-- Live view: the game's own minimap, moved into the window ----------------------------

local borrowed

local function restoreMinimapMask()
	if MinimapCluster and MinimapCluster.UpdateMinimapConfig
		and pcall(MinimapCluster.UpdateMinimapConfig, MinimapCluster) then
		return
	end
	pcall(Minimap.SetMaskTexture, Minimap, "ui-hud-minimap-frame-generic-mask")
end

local function sizeMinimap()
	if not borrowed then return end
	local side = math.max(50, liveHolder:GetWidth() - 4)
	Minimap:SetSize(side, side)
end

local function borrowMinimap()
	if borrowed or not Minimap then return end
	borrowed = {
		parent = Minimap:GetParent(),
		points = {},
		scale = Minimap:GetScale(),
		strata = Minimap:GetFrameStrata(),
		level = Minimap:GetFrameLevel(),
		zoom = Minimap:GetZoom(),
	}
	borrowed.width, borrowed.height = Minimap:GetSize()
	for i = 1, Minimap:GetNumPoints() do
		borrowed.points[i] = { Minimap:GetPoint(i) }
	end

	Minimap:SetParent(liveHolder)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("CENTER", liveHolder, "CENTER")
	Minimap:SetScale(1)
	Minimap:SetFrameStrata(liveHolder:GetFrameStrata())
	Minimap:SetFrameLevel(liveHolder:GetFrameLevel() + 2)
	pcall(Minimap.SetMaskTexture, Minimap, "Interface\\Buttons\\WHITE8X8")
	sizeMinimap()
	local zoom = ns.db.liveZoom or 0
	if zoom < Minimap:GetZoomLevels() then Minimap:SetZoom(zoom) end
end

local function returnMinimap()
	if not borrowed then return end
	ns.db.liveZoom = Minimap:GetZoom()
	Minimap:SetParent(borrowed.parent)
	Minimap:ClearAllPoints()
	for _, point in ipairs(borrowed.points) do
		Minimap:SetPoint(unpack(point))
	end
	Minimap:SetSize(borrowed.width, borrowed.height)
	Minimap:SetScale(borrowed.scale)
	Minimap:SetFrameStrata(borrowed.strata)
	Minimap:SetFrameLevel(borrowed.level)
	Minimap:SetZoom(borrowed.zoom)
	borrowed = nil
	restoreMinimapMask()
end

-- Layout ------------------------------------------------------------------------------------

local function layout()
	local w, h = content:GetSize()
	if not w or w <= 0 or h <= 0 then return end
	local scale = math.min(w / ART_W, h / ART_H)
	canvas:SetScale(scale)
	local dot = 22 / scale
	youDot:SetSize(dot, dot)
	local side = math.floor(math.min(w, h))
	liveHolder:SetSize(side, side)
	sizeMinimap()
end

local function nextStrata(strata)
	for i, s in ipairs(STRATA) do
		if s == strata then return STRATA[math.min(i + 1, #STRATA)] end
	end
	return "DIALOG"
end

local function dock()
	frame:Hide()
	frame:SetParent(WorldMapFrame)
	frame:ClearAllPoints()
	frame:SetAllPoints(WorldMapFrame.ScrollContainer or WorldMapFrame)
	frame:SetFrameStrata(nextStrata(WorldMapFrame:GetFrameStrata()))
	frame:SetFrameLevel(10)
	state.docked = true
end

local function undock()
	frame:Hide()
	frame:SetParent(UIParent)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER")
	frame:SetSize(ART_W * STANDALONE_SCALE + MARGIN * 2, ART_H * STANDALONE_SCALE + HEADER + FOOTER + MARGIN)
	frame:SetFrameStrata("HIGH")
	state.docked = false
end

-- Content -------------------------------------------------------------------------------------

local function isCurrent()
	return state.dungeonID ~= nil and ns.CurrentDungeon() == state.dungeonID
end

local function floors()
	return state.dungeonID and ns.GetFloors(state.dungeonID) or {}
end

local function currentMode()
	if #floors() == 0 then return "live" end
	return ns.db.mode
end

local function updateTiles()
	local floor = floors()[state.floor]
	for i, tile in ipairs(tiles) do
		if floor then
			tile:SetTexture(floor.prefix .. i)
			tile:Show()
		else
			tile:Hide()
		end
	end
end

local function updateYouDot()
	youDot:Hide()
	youDot.Pulse:Stop()
	if not isCurrent() then return end
	local spot = ns.GetRoomSpot(state.dungeonID, state.floor)
	if spot then
		youDot:ClearAllPoints()
		youDot:SetPoint("CENTER", canvas, "TOPLEFT", spot.x * ART_W, -spot.y * ART_H)
		youDot:Show()
		youDot.Pulse:Play()
	end
end

local function updateBosses()
	local lines = {}
	if isCurrent() or (not state.dungeonID and ns.CurrentInstance()) then
		for _, boss in ipairs(ns.GetBosses()) do
			if boss.killed then
				lines[#lines + 1] = "|cff808080" .. boss.name .. "|r |A:common-icon-checkmark:12:12|a"
			else
				lines[#lines + 1] = boss.name
			end
		end
	end
	if #lines > 0 then
		bossText:SetText("|cffffd100Bosses|r\n" .. table.concat(lines, "\n"))
		bossText:Show()
	else
		bossText:Hide()
	end
end

local function updateFooter(mode)
	local _, room = ns.CurrentRoom()
	local text
	if mode == "live" then
		text = "Live view of your minimap: your arrow, your group and the walls around you. Scroll to zoom."
		if room and ns.CurrentInstance() then
			text = "You are in: |cffffffff" .. room .. "|r.  " .. text
		end
	elseif isCurrent() then
		local spot = ns.GetRoomSpot(state.dungeonID, state.floor)
		if not room then
			text = "Ctrl+Click the map where you are to mark your room."
		elseif spot then
			text = "You are in: |cffffffff" .. room .. "|r (dot placed by room)."
		else
			text = "You are in: |cffffffff" .. room .. "|r. Ctrl+Click the map where this room is to mark it."
		end
	else
		text = "You are not inside this dungeon. Use Live inside a dungeon to see your position."
	end
	footerText:SetText(text)
end

local function update()
	if not frame or not frame:IsShown() then return end
	local mode = currentMode()
	local list = floors()
	local inst = ns.CurrentInstance()

	if state.dungeonID then
		title:SetText(ns.Dungeons[state.dungeonID].name)
	else
		title:SetText(inst and inst.name or "Dungeon Map")
	end

	mapTab:SetEnabled(#list > 0)
	if mode == "live" then
		liveTab:LockHighlight()
		mapTab:UnlockHighlight()
		canvas:Hide()
		noArtText:Hide()
		liveHolder:Show()
		borrowMinimap()
	else
		mapTab:LockHighlight()
		liveTab:UnlockHighlight()
		returnMinimap()
		liveHolder:Hide()
		canvas:Show()
		updateTiles()
		updateYouDot()
	end

	local showFloors = mode == "map" and #list > 1
	prevButton:SetShown(showFloors)
	nextButton:SetShown(showFloors)
	floorLabel:SetShown(mode == "map" and #list > 0)
	if list[state.floor] then
		floorLabel:SetText(#list > 1 and ("%s  (%d/%d)"):format(list[state.floor].name, state.floor, #list) or list[state.floor].name)
	end

	if mode == "live" and #list == 0 and (state.dungeonID or inst) then
		noArtText:SetText("The game has no full map for this dungeon, so only the live view is available.")
		noArtText:Show()
	end

	updateBosses()
	updateFooter(mode)
end

local function setFloor(floor)
	local list = floors()
	if not list[floor] then return end
	state.floor = floor
	ns.RememberFloor(state.dungeonID, floor)
	update()
end

local function onCanvasClick(self, button)
	if not IsControlKeyDown() then return end
	if not isCurrent() then
		ns.Print("You can only mark rooms of the dungeon you are in.")
		return
	end
	if button == "RightButton" then
		ns.ForgetRoom(state.dungeonID, state.floor)
		return
	end
	local cx, cy = GetCursorPosition()
	local scale = self:GetEffectiveScale()
	local x = (cx / scale - self:GetLeft()) / self:GetWidth()
	local y = (self:GetTop() - cy / scale) / self:GetHeight()
	if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
		ns.MarkRoom(state.dungeonID, state.floor, x, y)
	end
end

-- Building the window ---------------------------------------------------------------------

local function makeButton(parent, text, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	return button
end

local function create()
	frame = CreateFrame("Frame", "ForeverDungeonMapFrame", UIParent)
	frame:Hide()
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetToplevel(true)
	tinsert(UISpecialFrames, "ForeverDungeonMapFrame")

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.03, 0.03, 0.05, 0.97)

	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() if not state.docked then frame:StartMoving() end end)
	header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetAllPoints()
	headerBg:SetColorTexture(0.1, 0.1, 0.13, 1)

	title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", 10, 0)

	closeButton = CreateFrame("Button", nil, header, "UIPanelCloseButton")
	closeButton:SetPoint("RIGHT", 0, 0)
	closeButton:SetScript("OnClick", function() frame:Hide() end)
	closeButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText(state.docked and "Show the normal world map" or "Close")
		GameTooltip:Show()
	end)
	closeButton:SetScript("OnLeave", GameTooltip_Hide)

	mapTab = makeButton(header, "Full map", 84)
	mapTab:SetPoint("RIGHT", closeButton, "LEFT", -4, 0)
	mapTab:SetScript("OnClick", function() ns.db.mode = "map"; update() end)
	liveTab = makeButton(header, "Live", 64)
	liveTab:SetPoint("RIGHT", mapTab, "LEFT", -4, 0)
	liveTab:SetScript("OnClick", function() ns.db.mode = "live"; update() end)

	floorLabel = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	floorLabel:SetPoint("CENTER")
	prevButton = makeButton(header, "<", 26)
	prevButton:SetPoint("RIGHT", floorLabel, "LEFT", -8, 0)
	prevButton:SetScript("OnClick", function() setFloor(state.floor - 1) end)
	nextButton = makeButton(header, ">", 26)
	nextButton:SetPoint("LEFT", floorLabel, "RIGHT", 8, 0)
	nextButton:SetScript("OnClick", function() setFloor(state.floor + 1) end)

	footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	footerText:SetPoint("BOTTOMLEFT", MARGIN + 4, 7)
	footerText:SetPoint("BOTTOMRIGHT", -MARGIN - 4, 7)
	footerText:SetJustifyH("LEFT")
	footerText:SetWordWrap(false)

	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", MARGIN, -HEADER - 2)
	content:SetPoint("BOTTOMRIGHT", -MARGIN, FOOTER)
	content:SetScript("OnSizeChanged", layout)

	canvas = CreateFrame("Frame", nil, content)
	canvas:SetSize(ART_W, ART_H)
	canvas:SetPoint("CENTER")
	canvas:EnableMouse(true)
	canvas:SetScript("OnMouseUp", onCanvasClick)
	tiles = {}
	for i = 1, 12 do
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		local w = col == 3 and (ART_W - 3 * TILE) or TILE
		local h = row == 2 and (ART_H - 2 * TILE) or TILE
		local tile = canvas:CreateTexture(nil, "ARTWORK")
		tile:SetSize(w, h)
		tile:SetPoint("TOPLEFT", col * TILE, -row * TILE)
		tile:SetTexCoord(0, w / TILE, 0, h / TILE)
		tiles[i] = tile
	end

	youDot = CreateFrame("Frame", nil, canvas)
	youDot:SetFrameLevel(canvas:GetFrameLevel() + 5)
	local ring = youDot:CreateTexture(nil, "ARTWORK")
	ring:SetAllPoints()
	ring:SetTexture("Interface\\COMMON\\Indicator-Yellow")
	local dot = youDot:CreateTexture(nil, "OVERLAY")
	dot:SetAllPoints()
	dot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
	local pulse = youDot:CreateAnimationGroup()
	pulse:SetLooping("REPEAT")
	local grow = pulse:CreateAnimation("Scale")
	grow:SetTarget(ring)
	grow:SetScaleFrom(1, 1)
	grow:SetScaleTo(2.6, 2.6)
	grow:SetDuration(1.2)
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetTarget(ring)
	fade:SetFromAlpha(0.9)
	fade:SetToAlpha(0)
	fade:SetDuration(1.2)
	youDot.Pulse = pulse
	youDot:Hide()

	liveHolder = CreateFrame("Frame", nil, content)
	liveHolder:SetPoint("CENTER")
	liveHolder:EnableMouseWheel(true)
	liveHolder:SetScript("OnMouseWheel", function(_, delta)
		if not borrowed then return end
		local zoom = math.max(0, math.min(Minimap:GetZoomLevels() - 1, Minimap:GetZoom() + delta))
		Minimap:SetZoom(zoom)
	end)
	local liveBorder = liveHolder:CreateTexture(nil, "BACKGROUND")
	liveBorder:SetAllPoints()
	liveBorder:SetColorTexture(0.35, 0.3, 0.2, 1)

	bossText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	bossText:SetPoint("TOPRIGHT", -8, -8)
	bossText:SetJustifyH("RIGHT")
	bossText:SetShadowOffset(1, -1)

	noArtText = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	noArtText:SetPoint("TOPLEFT", 8, -8)

	frame:SetScript("OnShow", function()
		layout()
		update()
	end)
	frame:SetScript("OnHide", returnMinimap)

	undock()
end

-- Opening ------------------------------------------------------------------------------------

local function openFor(dungeonID, docked)
	if not frame then create() end
	if docked then dock() else undock() end
	state.dungeonID = dungeonID
	if dungeonID then
		state.floor = isCurrent() and ns.PickFloor(dungeonID) or 1
	end
	state.room = ns.CurrentRoom()
	frame:Show()
end

function ns.ShowWindow(dungeonID, mode)
	if mode then ns.db.mode = mode end
	openFor(dungeonID, false)
end

function ns.ToggleWindow()
	if frame and frame:IsShown() then
		frame:Hide()
		return
	end
	openFor(ns.CurrentDungeon() or state.dungeonID, false)
end

function ns.ShownDungeon()
	return frame and frame:IsShown() and state.dungeonID or nil
end

ns.OnRefresh(function()
	if not frame or not frame:IsShown() then return end
	local room = ns.CurrentRoom()
	if room ~= state.room then
		state.room = room
		if isCurrent() and ns.FloorForRoomKnown(state.dungeonID) then
			state.floor = ns.PickFloor(state.dungeonID)
		end
	end
	update()
end)

local function hookWorldMap()
	if not WorldMapFrame or ns.worldMapHooked then return end
	ns.worldMapHooked = true
	WorldMapFrame:HookScript("OnShow", function()
		if not ns.db or not ns.db.autoOpen or not ns.CurrentInstance() then return end
		openFor(ns.CurrentDungeon(), true)
	end)
	WorldMapFrame:HookScript("OnHide", function()
		if frame and state.docked then frame:Hide() end
	end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self)
	hookWorldMap()
	if ns.worldMapHooked then self:UnregisterAllEvents() end
end)
