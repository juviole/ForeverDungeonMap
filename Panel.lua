local _, ns = ...

local WIDTH = 230
local ROW_HEIGHT = 16
local PADDING = 10

local panel
local rows = {}

local function createRow(index)
	local row = CreateFrame("Button", nil, panel)
	row:SetSize(WIDTH - PADDING * 2, ROW_HEIGHT)
	row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Text:SetPoint("LEFT")
	row.Text:SetPoint("RIGHT")
	row.Text:SetJustifyH("LEFT")
	row.Text:SetWordWrap(false)
	row:SetScript("OnClick", function(self) ns.OpenJournal(self.boss) end)
	rows[index] = row
	return row
end

function ns.CreatePanel(parent)
	panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	panel:SetWidth(WIDTH)
	panel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8)
	panel:SetFrameStrata("DIALOG")
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0, 0, 0, 0.75)
	panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)

	panel.Title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.Title:SetPoint("TOPLEFT", PADDING, -PADDING)
	panel.Title:SetPoint("RIGHT", -PADDING, 0)
	panel.Title:SetJustifyH("LEFT")

	panel.Room = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.Room:SetPoint("TOPLEFT", panel.Title, "BOTTOMLEFT", 0, -4)
	panel.Room:SetPoint("RIGHT", -PADDING, 0)
	panel.Room:SetJustifyH("LEFT")

	panel.Hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.Hint:SetWidth(WIDTH - PADDING * 2)
	panel.Hint:SetJustifyH("LEFT")
	panel.Hint:SetWordWrap(true)

	panel:Hide()
	return panel
end

function ns.UpdatePanel()
	if not panel then return end
	local mapID = WorldMapFrame:GetMapID()
	if not ns.db or not ns.db.panel or not ns.IsDungeonMap(mapID) then
		panel:Hide()
		return
	end

	local info = C_Map.GetMapInfo(mapID)
	local floors = ns.GetFloors(mapID)
	local floorName
	if #floors > 1 then
		for _, f in ipairs(floors) do
			if f.mapID == mapID then floorName = f.name end
		end
	end
	if floorName and floorName ~= info.name then
		panel.Title:SetText(("%s |cffaaaaaa- %s|r"):format(info.name, floorName))
	else
		panel.Title:SetText(info.name)
	end

	local inside = ns.IsCurrentDungeon(mapID)
	local hint
	if inside then
		local spot, room = ns.GetRoomSpot(mapID)
		if room then
			panel.Room:SetText("You are in: |cffffffff" .. room .. "|r")
			if not spot then
				hint = "Ctrl+Click the map where this room is to mark it."
			end
		else
			panel.Room:SetText("You are inside this dungeon.")
		end
	else
		local current = ns.ResolveCurrent()
		panel.Room:SetText(current and "You are in a different dungeon." or "You are not inside.")
	end

	local bosses = ns.GetBosses(mapID)
	local anchor = panel.Room
	local shown = 0
	for i, boss in ipairs(bosses) do
		local row = rows[i] or createRow(i)
		row.boss = boss
		local name = boss.name
		if boss.killed then
			name = ("|cff808080%d. %s|r |A:common-icon-checkmark:12:12|a"):format(boss.index, name)
		else
			name = ("|cffffd100%d.|r %s"):format(boss.index, name)
		end
		if not boss.x then
			name = name .. " |cff808080(other floor or unknown)|r"
		end
		row.Text:SetText(name)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, i == 1 and -6 or 0)
		row:Show()
		anchor = row
		shown = i
	end
	for i = shown + 1, #rows do
		rows[i]:Hide()
	end
	if shown == 0 then
		hint = (hint and hint .. "\n" or "") .. "The game has no boss list for this map. Bosses you kill in a marked room are added here."
	end

	panel.Hint:ClearAllPoints()
	panel.Hint:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
	panel.Hint:SetText(hint or "")
	panel.Hint:SetShown(hint ~= nil)

	local height = PADDING * 2 + panel.Title:GetStringHeight() + 4 + panel.Room:GetStringHeight()
	if shown > 0 then height = height + 6 + shown * ROW_HEIGHT end
	if hint then height = height + 6 + panel.Hint:GetStringHeight() end
	panel:SetHeight(height)
	panel:Show()
end
