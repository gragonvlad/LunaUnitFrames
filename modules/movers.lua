local L = LunaUF.L
local Movers = {}
local originalEnvs = {}
local unitConfig = {}
local attributeBlacklist = {["showplayer"] = true, ["showraid"] = true, ["showparty"] = true, ["showsolo"] = true, ["initial-unitwatch"] = true}
local OnDragStop, OnDragStart, configEnv
LunaUF:RegisterModule(Movers, "movers")

local function getValue(func, unit, value)
	unit = string.gsub(unit, "(%d+)", "")
	if( unitConfig[func .. unit] == nil ) then unitConfig[func .. unit] = value end
	return unitConfig[func .. unit]
end

local function createConfigEnv()
	if( configEnv ) then return end
	configEnv = setmetatable({
		GetRaidTargetIndex = function(unit) return getValue("GetRaidTargetIndex", unit, math.random(1, 8)) end,
		GetLootMethod = function(unit) return "master", 0, 0 end,
		GetComboPoints = function() return MAX_COMBO_POINTS end,
		UnitInRaid = function() return true end,
		UnitInParty = function() return true end,
--		UnitIsUnit = function(unitA, unitB) return true end,
		UnitIsDeadOrGhost = function(unit) return false end,
		UnitIsConnected = function(unit) return true end,
		UnitLevel = function(unit) return MAX_PLAYER_LEVEL end,
--		UnitIsPlayer = function(unit) return unit ~= "pet" and not string.match(unit, "(%w+)pet") end,
		UnitHealth = function(unit) return getValue("UnitHealth", unit, math.random(20000, 50000)) end,
		UnitHealthMax = function(unit) return 50000 end,
		UnitPower = function(unit, powerType)
			return getValue("UnitPower", unit, math.random(20000, 50000))
		end,
		UnitPowerMax = function(unit, powerType)
			if powerType == Enum.PowerType.ComboPoints then
				return 5
			end

			return 50000
		end,
--		UnitExists = function(unit) return true end,
		UnitIsGroupLeader = function() return true end,
		UnitIsPVP = function(unit) return true end,
		UnitIsDND = function(unit) return false end,
		UnitIsAFK = function(unit) return false end,
		UnitFactionGroup = function(unit) return _G.UnitFactionGroup("player") end,
		UnitAffectingCombat = function() return true end,
		UnitCastingInfo = function(unit)
			-- 1 -> 10: spell, displayName, icon, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID
			local data = unitConfig["UnitCastingInfo" .. unit] or {}
			if( not data[5] or GetTime() < data[5] ) then
				data[1] = L["Test spell"]
				data[2] = L["Test spell"]
				data[3] = "Interface\\Icons\\Spell_Nature_Rejuvenation"
				data[4] = GetTime() * 1000
				data[5] = data[4] + 60000
				data[6] = false
				data[7] = math.floor(GetTime())
				data[8] = math.random(0, 100) < 25
				data[9] = 1000
				unitConfig["UnitCastingInfo" .. unit] = data
			end
			
			return unpack(data)
		end,
--		UnitIsFriend = function(unit) return true end,
		GetReadyCheckStatus = function(unit)
			local status = getValue("GetReadyCheckStatus", unit, math.random(1, 3))
			return status == 1 and "ready" or status == 2 and "notready" or "waiting"
		end,
		UnitPowerType = function(unit)
			return _G.UnitPowerType("player")
		end,
		UnitAura = function(unit, id, filter)
			if( type(id) ~= "number" or id > 40 ) then return end
			
			local texture = filter == "HELPFUL" and "Interface\\Icons\\Spell_ChargePositive" or "Interface\\Icons\\Spell_ChargeNegative"
			local mod = id % 5
			local auraType = mod == 0 and "Magic" or mod == 1 and "Curse" or mod == 2 and "Poison" or mod == 3 and "Disease" or "none"
			return L["Test Aura"], texture, id, auraType, 0, 0, (math.random(0,1) > 0) and "player", id % 6 == 0
		end,
		UnitName = function(unit)
			local unitID = string.match(unit, "(%d+)")
			if( unitID ) then
				return string.format("%s #%d", L.units[string.gsub(unit, "(%d+)", "")] or unit, unitID)
			end
			
			return L[unitType]
		end,
		UnitClass = function(unit)
			return _G.UnitClass("player")
		end,
	}, {
		__index = _G,
		__newindex = function(tbl, key, value) _G[key] = value end,
	})
end

local function prepareChildUnits(header, ...)
	for i=1, select("#", ...) do
		local frame = select(i, ...)
		if( frame.unitType and not frame.configUnitID ) then
			LunaUF.Units.frameList[frame] = true
			frame.configUnitID = header.groupID and (header.groupID * 5) - 5 + i or i
			frame:SetAttribute("unit", "player")
		end
	end
end

local function OnEnter(self)
	local tooltip = self.tooltipText or self.configUnitID and string.format("%s #%d", L[self.unitType], self.configUnitID) or L[self.unitType] or self.unitType

	GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
	GameTooltip:SetText(tooltip, 1, 0.81, 0, 1, true)
	GameTooltip:Show()
end

local function OnLeave(self)
	GameTooltip:Hide()
end

local function setupUnits()
	for frame in pairs(LunaUF.Units.frameList) do
		if( frame.configMode ) then
			-- Units visible, but it's not supposed to be
			if( frame:IsVisible() and not LunaUF.db.profile.units[frame.unitType].enabled ) then
				RegisterUnitWatch(frame, frame.hasStateWatch)
				if( not UnitExists(frame.unit) ) then frame:Hide() end
				
			-- Unit's not visible and it's enabled so it should
			elseif( not frame:IsVisible() and LunaUF.db.profile.units[frame.unitType].enabled ) then
				UnregisterUnitWatch(frame)

				frame:SetAttribute("state-unitexists", true)
				frame:FullUpdate()
				frame:Show()
			end
		elseif( not frame.configMode and LunaUF.db.profile.units[frame.unitType].enabled ) then
			frame.originalUnit = frame:GetAttribute("unit")
			frame.originalOnEnter = frame.OnEnter
			frame.originalOnLeave = frame.OnLeave
			frame.originalOnUpdate = frame:GetScript("OnUpdate")
			frame:SetMovable(true)
			frame:SetScript("OnDragStop", OnDragStop)
			frame:SetScript("OnDragStart", OnDragStart)
			frame.OnEnter = OnEnter
			frame.OnLeave = OnLeave
			frame:SetScript("OnEvent", nil)
			frame:SetScript("OnUpdate", nil)
			frame:RegisterForDrag("LeftButton")
			frame.configMode = true
			frame.unitOwner = nil
			frame.originalMenu = frame.menu
			frame.menu = nil
			
			LunaUF.Units.OnAttributeChanged(frame, "unit", "player")

			if( frame.healthBar ) then frame.healthBar:SetScript("OnUpdate", nil) end
			if( frame.powerBar ) then frame.powerBar:SetScript("OnUpdate", nil) end
			if( frame.indicators ) then frame.indicators:SetScript("OnUpdate", nil) end
			
			UnregisterUnitWatch(frame)
			frame:FullUpdate()
			frame:Show()
		end
	end
end

function Movers:Enable()
	createConfigEnv()

	-- Setup the headers
	for _, header in pairs(LunaUF.Units.headerFrames) do
		for key in pairs(attributeBlacklist) do
			header:SetAttribute(key, nil)
		end
		
		local config = LunaUF.db.profile.units[header.unitType]
		if( config.frameSplit ) then
			header:SetAttribute("startingIndex", -4)
		elseif( config.maxColumns ) then
			local maxUnits = MAX_RAID_MEMBERS
			if( config.filters ) then
				for _, enabled in pairs(config.filters) do
					if( not enabled ) then
						maxUnits = maxUnits - 5
					end
				end
			end
					
			header:SetAttribute("startingIndex", -math.min(config.maxColumns * config.unitsPerColumn, maxUnits) + 1)
		elseif( LunaUF[header.unitType .. "Units"] ) then
			header:SetAttribute("startingIndex", -#(LunaUF[header.unitType .. "Units"]) + 1)
		end
		
		header.startingIndex = header:GetAttribute("startingIndex")
		header:SetMovable(true)
		prepareChildUnits(header, header:GetChildren())
	end

	-- Setup the test env
	if( not self.isEnabled ) then
--		for _, func in pairs(LunaUF.tagFunc) do
--			if( type(func) == "function" ) then
--				originalEnvs[func] = getfenv(func)
--				setfenv(func, configEnv)
--			end
--		end

		for _, module in pairs(LunaUF.modules) do
			if( module.moduleName ) then
				for key, func in pairs(module) do
					if( type(func) == "function" ) then
						originalEnvs[module[key]] = getfenv(module[key])
						setfenv(module[key], configEnv)
					end
				end
			end
		end
	end
	
	-- Why is this called twice you ask? Child units are created on the OnAttributeChanged call
	-- so the first call gets all the parent units, the second call gets the child units
	setupUnits()
	setupUnits()

	-- Don't show the dialog if the configuration is opened through the configmode spec
--	if( not self.isConfigModeSpec ) then
--		self:CreateInfoFrame()
--		self.infoFrame:Show()
--	elseif( self.infoFrame ) then
--		self.infoFrame:Hide()
--	end
	
	self.isEnabled = true
end

function Movers:Disable()
	if( not self.isEnabled ) then return nil end
	
	for func, env in pairs(originalEnvs) do
		setfenv(func, env)
		originalEnvs[func] = nil
	end
	
	for frame in pairs(LunaUF.Units.frameList) do
		if( frame.configMode ) then
			if( frame.isMoving ) then
				frame:GetScript("OnDragStop")(frame)
			end
			
			frame.configMode = nil
			frame.unitOwner = nil
			frame.unit = nil
			frame.configUnitID = nil
			frame.menu = frame.originalMenu
			frame.originalMenu = nil
			frame.Hide = frame.originalHide
			frame:SetAttribute("unit", frame.originalUnit)
			frame:SetScript("OnDragStop", nil)
			frame:SetScript("OnDragStart", nil)
			frame:SetScript("OnEvent", frame:IsVisible() and LunaUF.Units.OnEvent or nil)
			frame:SetScript("OnUpdate", frame.originalOnUpdate)
			frame.OnEnter = frame.originalOnEnter
			frame.OnLeave = frame.originalOnLeave
			frame:SetMovable(false)
			frame:RegisterForDrag()

			RegisterUnitWatch(frame, frame.hasStateWatch)
			if( not UnitExists(frame.unit) ) then frame:Hide() end
		end
	end
			
	for type, header in pairs(LunaUF.Units.headerFrames) do
		header:SetMovable(false)
		header:SetAttribute("startingIndex", 1)
		header:SetAttribute("initial-unitWatch", true)
		
		if( header.unitType == type ) then
			LunaUF.Units:ReloadHeader(header.unitType)
		end
	end
	
	LunaUF.Layout:Reload()
	
	-- Don't store these so everything can be GCed
	unitConfig = {}

--	if( self.infoFrame ) then
--		self.infoFrame:Hide()
--	end
	
	self.isEnabled = nil
end

OnDragStart = function(self)
	if( not self:IsMovable() ) then return end
	
	if( LunaUF.Units.headerUnits[self.unitType] ) then
		self = self:GetParent()
	end

	self.isMoving = true
	self:StartMoving()
end

OnDragStop = function(self)
	if( not self:IsMovable() ) then return end
	if( LunaUF.Units.headerUnits[self.unitType] ) then
		self = self:GetParent()
	end

	self.isMoving = nil
	self:StopMovingOrSizing()
	
	-- When dragging the frame around, Blizzard changes the anchoring based on the closet portion of the screen
	-- When a widget is near the top left it uses top left, near the left it uses left and so on, which messes up positioning for header frames
	local scale = (self:GetScale() * UIParent:GetScale()) or 1
	local position = LunaUF.db.profile.units[self.unitType]
	if not position.x then
		position = LunaUF.db.profile.units[self.unitType].positions[self.groupID]
	end
	local anchor = position.anchorTo and _G[position.anchorTo]

	local point, anchorTo, relativePoint, x, y = self:GetPoint()

	if position.anchorTo ~= "UIParent" then
		x = self:GetLeft() - anchor:GetLeft()
		y = self:GetTop() - anchor:GetTop()
		point = "TOPLEFT"
		relativePoint = "TOPLEFT"
		scale = 1
	elseif anchorTo then
		x = 0
		y = 0
		point = "CENTER"
		relativePoint = "CENTER"
	end


	position.x = x * scale
	position.y = y * scale
	position.point = point
	position.relativePoint = relativePoint

	LunaUF.Layout:AnchorFrame(self, position)

	-- Notify the configuration it can update itself now
	local ACR = LibStub("AceConfigRegistry-3.0", true)
	if( ACR ) then
		ACR:NotifyChange("LunaUnitFrames")
	end
end

function Movers:Update()
	if( not LunaUF.db.profile.locked ) then
		self:Enable()
	elseif( LunaUF.db.profile.locked ) then
		self:Disable()
	end
end