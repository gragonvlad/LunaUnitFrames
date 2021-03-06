local Cast = {}
local L = LunaUF.L
local SML = LibStub:GetLibrary("LibSharedMedia-3.0")
local FADE_TIME = 0.30

LunaUF:RegisterModule(Cast, "castBar", L["Cast bar"], true)

-- I'm not really thrilled with this method of detecting fake unit casts, mostly because it's inefficient and ugly
local function monitorFakeCast(self)
	local spell, displayName, icon, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(self.parent.unit)
	local isChannelled
	if( not spell ) then
		spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID = UnitChannelInfo(self.parent.unit)
		isChannelled = true
	end
	
	-- Cast started
	if( not self.endTime and endTime ) then
		self.endTime = endTime
		self.notInterruptible = notInterruptible
		self.spellName = spell
		self.spellID = spellID
		Cast:UpdateCast(self.parent, self.parent.unit, isChannelled, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID)
	-- Cast stopped
	elseif( self.endTime and not endTime ) then
		if( GetTime() <= (self.endTime / 1000) ) then
			Cast:EventInterruptCast(self.parent, nil, self.parent.unit, nil, self.spellID)
		end
		
		self.notInterruptible = nil
		self.spellName = nil
		self.endTime = nil
		return
	end
	
	-- Cast delayed
	if( self.endTime and endTime ~= self.endTime ) then
		self.endTime = endTime
		Cast:UpdateDelay(self.parent, spell, displayName, icon, startTime, endTime)
	end

	-- Cast interruptible status changed
	if( self.spellName and self.notInterruptible ~= notInterruptible ) then
		self.notInterruptible = notInterruptible
		if( notInterruptible ) then
			Cast:EventUninterruptible(self.parent)
		else
			Cast:EventInterruptible(self.parent)
		end
	end
end

local function createFakeCastMonitor(frame)
	if( not frame.castBar.monitor ) then
		frame.castBar.monitor = C_Timer.NewTicker(0.10, monitorFakeCast)
		frame.castBar.monitor.parent = frame
	end
end

local function cancelFakeCastMonitor(frame)
	if( frame.castBar and frame.castBar.monitor ) then
		frame.castBar.monitor:Cancel()
		frame.castBar.monitor = nil
	end
end

function Cast:OnEnable(frame)
	if( not frame.castBar ) then
		frame.castBar = CreateFrame("Frame", nil, frame)
		frame.castBar.bar = LunaUF.Units:CreateBar(frame)
		frame.castBar.background = frame.castBar.bar.background
		frame.castBar.bar.parent = frame
		frame.castBar.bar.background = frame.castBar.background
		
		frame.castBar.icon = frame.castBar.bar:CreateTexture(nil, "ARTWORK")
--		frame.castBar.bar.name = frame.castBar.bar:CreateFontString(nil, "ARTWORK")
--		frame.castBar.bar.time = frame.castBar.bar:CreateFontString(nil, "ARTWORK")
	end
	
	if( LunaUF.fakeUnits[frame.unitType] ) then
		createFakeCastMonitor(frame)
		frame:RegisterUpdateFunc(self, "UpdateFakeCast")
		return
	end
	
	frame:RegisterUnitEvent("UNIT_SPELLCAST_START", self, "EventUpdateCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", self, "EventStopCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", self, "EventStopCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", self, "EventInterruptCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", self, "EventDelayCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", self, "EventCastSucceeded")
	
	frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", self, "EventUpdateChannel")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", self, "EventStopCast")
	--frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_INTERRUPTED", self, "EventInterruptCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", self, "EventDelayChannel")

	frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", self, "EventInterruptible")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", self, "EventUninterruptible")
	
	frame:RegisterUpdateFunc(self, "UpdateCurrentCast")
end

function Cast:OnLayoutApplied(frame, config)
	if( not frame.visibility.castBar ) then return end
	
	-- Set textures
	frame.castBar.bar:SetStatusBarTexture(LunaUF.Layout:LoadMedia(SML.MediaType.STATUSBAR, frame.unitType))
	frame.castBar.bar:GetStatusBarTexture():SetHorizTile(false)
	frame.castBar.bar:SetStatusBarColor(0, 0, 0, 0)
	frame.castBar.background:SetVertexColor(0, 0, 0, 0)
	frame.castBar.background:SetHorizTile(false)
	
	-- Setup fill
	frame.castBar.bar:SetOrientation(config.castBar.vertical and "VERTICAL" or "HORIZONTAL")
	frame.castBar.bar:SetReverseFill(config.castBar.reverse and true or false)

	-- Setup the main bar + icon
	frame.castBar.bar:ClearAllPoints()
	frame.castBar.bar:SetHeight(frame.castBar:GetHeight())
	frame.castBar.bar:SetValue(0)
	frame.castBar.bar:SetMinMaxValues(0, 1)
	
	-- Use the entire bars width and show the icon
	if( config.castBar.icon == "HIDE" ) then
		frame.castBar.bar:SetWidth(frame.castBar:GetWidth())
		frame.castBar.bar:SetAllPoints(frame.castBar)
		frame.castBar.icon:Hide()
	-- Shift the bar to the side and show an icon
	else
		frame.castBar.bar:SetWidth(frame.castBar:GetWidth() - frame.castBar:GetHeight())
		frame.castBar.icon:ClearAllPoints()
		frame.castBar.icon:SetWidth(frame.castBar:GetHeight())
		frame.castBar.icon:SetHeight(frame.castBar:GetHeight())
		frame.castBar.icon:Show()

		if( config.castBar.icon == "LEFT" ) then
			frame.castBar.bar:SetPoint("TOPLEFT", frame.castBar, "TOPLEFT", frame.castBar:GetHeight() + 1, 0)
			frame.castBar.icon:SetPoint("TOPRIGHT", frame.castBar.bar, "TOPLEFT", -1, 0)
		else
			frame.castBar.bar:SetPoint("TOPLEFT", frame.castBar, "TOPLEFT", 1, 0)
			frame.castBar.icon:SetPoint("TOPLEFT", frame.castBar.bar, "TOPRIGHT", 0, 0)
		end
	end
	
	-- Set the font at the very least, so it doesn't error when we set text on it even if it isn't being shown
--	LunaUF.Layout:ToggleVisibility(frame.castBar.bar.name, config.castBar.name.enabled)
--	if( config.castBar.name.enabled ) then
--		frame.castBar.bar.name:SetParent(frame.highFrame)
--		frame.castBar.bar.name:SetWidth(frame.castBar.bar:GetWidth() * 0.75)
--		frame.castBar.bar.name:SetHeight(LunaUF.db.profile.font.size + 1)
--		frame.castBar.bar.name:SetJustifyH(LunaUF.Layout:GetJustify(config.castBar.name))

--		ShadowUF.Layout:AnchorFrame(frame.castBar.bar, frame.castBar.bar.name, config.castBar.name)
--		ShadowUF.Layout:SetupFontString(frame.castBar.bar.name, config.castBar.name.size)
--	end
	
--	ShadowUF.Layout:ToggleVisibility(frame.castBar.bar.time, config.castBar.time.enabled)
--	if( config.castBar.time.enabled ) then
--		frame.castBar.bar.time:SetParent(frame.highFrame)
--		frame.castBar.bar.time:SetWidth(frame.castBar.bar:GetWidth() * 0.25)
--		frame.castBar.bar.time:SetHeight(ShadowUF.db.profile.font.size + 1)
--		frame.castBar.bar.time:SetJustifyH(ShadowUF.Layout:GetJustify(config.castBar.time))

--		ShadowUF.Layout:AnchorFrame(frame.castBar.bar, frame.castBar.bar.time, config.castBar.time)
--		ShadowUF.Layout:SetupFontString(frame.castBar.bar.time, config.castBar.time.size)
--	end
	
	-- So we don't have to check the entire thing in an OnUpdate
--	frame.castBar.bar.time.enabled = config.castBar.time.enabled
	
	if( config.castBar.autoHide and not UnitCastingInfo(frame.unit) and not UnitChannelInfo(frame.unit) ) then
		LunaUF.Layout:SetBarVisibility(frame, "castBar", false)
	end
end

function Cast:OnDisable(frame, unit)
	frame:UnregisterAll(self)

	if( frame.castBar ) then
		cancelFakeCastMonitor(frame)

--		frame.castBar.bar.name:Hide()
--		frame.castBar.bar.time:Hide()
		frame.castBar.bar:Hide()
	end
end

-- Easy coloring
local function setBarColor(self, r, g, b)
	self.parent:SetBlockColor(self, "castBar", r, g, b)
end

-- Cast OnUpdates
local function fadeOnUpdate(self, elapsed)
	self.fadeElapsed = self.fadeElapsed - elapsed
	
	if( self.fadeElapsed <= 0 ) then
		self.fadeElapsed = nil
--		self.name:Hide()
--		self.time:Hide()
		self:Hide()
		
		local frame = self:GetParent()
		if( LunaUF.db.profile.units[frame.unitType].castBar.autoHide ) then
			LunaUF.Layout:SetBarVisibility(frame, "castBar", false)
		end
	else
		local alpha = self.fadeElapsed / self.fadeStart
		self:SetAlpha(alpha)
--		self.time:SetAlpha(alpha)
--		self.name:SetAlpha(alpha)
	end
end

local function castOnUpdate(self, elapsed)
	local time = GetTime()
	self.elapsed = self.elapsed + (time - self.lastUpdate)
	self.lastUpdate = time
	self:SetValue(self.elapsed)
	
	if( self.elapsed <= 0 ) then
		self.elapsed = 0
	end
	
--	if( self.time.enabled ) then
--		local timeLeft = self.endSeconds - self.elapsed
--		if( timeLeft <= 0 ) then
--			self.time:SetText("0.0")
--		elseif( self.pushback == 0 ) then
--			self.time:SetFormattedText("%.1f", timeLeft)
--		else
--			self.time:SetFormattedText("|cffff0000%.1f|r %.1f", self.pushback, timeLeft)
--		end
--	end

	-- Cast finished, do a quick fade
	if( self.elapsed >= self.endSeconds ) then
--		setBarColor(self, LunaUF.db.profile.colors.finished.r, LunaUF.db.profile.colors.finished.g, LunaUF.db.profile.colors.finished.b)

		self.spellName = nil
		self.fadeElapsed = FADE_TIME
		self.fadeStart = FADE_TIME
		self:SetScript("OnUpdate", fadeOnUpdate)
	end
end

local function channelOnUpdate(self, elapsed)
	local time = GetTime()
	self.elapsed = self.elapsed - (time - self.lastUpdate)
	self.lastUpdate = time
	self:SetValue(self.elapsed)

	if( self.elapsed <= 0 ) then
		self.elapsed = 0
	end

--	if( self.time.enabled ) then
--		if( self.elapsed <= 0 ) then
--			self.time:SetText("0.0")
--		elseif( self.pushback == 0 ) then
--			self.time:SetFormattedText("%.1f", self.elapsed)
--		else
--			self.time:SetFormattedText("|cffff0000%.1f|r %.1f", self.pushback, self.elapsed)
--		end
--	end

	-- Channel finished, do a quick fade
	if( self.elapsed <= 0 ) then
--		setBarColor(self, LunaUF.db.profile.colors.finished.r, LunaUF.db.profile.colors.finished.g, LunaUF.db.profile.colors.finished.b)

		self.spellName = nil
		self.fadeElapsed = FADE_TIME
		self.fadeStart = FADE_TIME
		self:SetScript("OnUpdate", fadeOnUpdate)
	end
end

function Cast:UpdateCurrentCast(frame)
	if( UnitCastingInfo(frame.unit) ) then
		local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(frame.unit)
		self:UpdateCast(frame, frame.unit, false, name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID)
	elseif( UnitChannelInfo(frame.unit) ) then
		local name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID = UnitChannelInfo(frame.unit)
		self:UpdateCast(frame, frame.unit, true, name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID)
	else
		if( LunaUF.db.profile.units[frame.unitType].castBar.autoHide ) then
			LunaUF.Layout:SetBarVisibility(frame, "castBar", false)
		end

		setBarColor(frame.castBar.bar, 0, 0, 0)
		
		frame.castBar.bar.spellName = nil
--		frame.castBar.bar.name:Hide()
--		frame.castBar.bar.time:Hide()
		frame.castBar.bar:Hide()
	end
end

-- Cast updated/changed
function Cast:EventUpdateCast(frame)
	local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(frame.unit)
	self:UpdateCast(frame, frame.unit, false, name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID)
end

function Cast:EventDelayCast(frame)
	local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(frame.unit)
	self:UpdateDelay(frame, name, text, texture, startTime, endTime)
end

-- Channel updated/changed
function Cast:EventUpdateChannel(frame)
	local name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID = UnitChannelInfo(frame.unit)
	self:UpdateCast(frame, frame.unit, true, name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID)
end

function Cast:EventDelayChannel(frame)
	local name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID = UnitChannelInfo(frame.unit)
	self:UpdateDelay(frame, name, text, texture, startTime, endTime)
end

-- Cast finished
function Cast:EventStopCast(frame, event, unit, castID, spellID)
	local cast = frame.castBar.bar
	if( cast.spellID ~= spellID or ( event == "UNIT_SPELLCAST_FAILED" and cast.isChannelled ) ) then return end
--	if( cast.time.enabled ) then
--		cast.time:SetText("0.0")
--	end

--	setBarColor(cast, LunaUF.db.profile.colors.interrupted.r, LunaUF.db.profile.colors.interrupted.g, LunaUF.db.profile.colors.interrupted.b)
	if( LunaUF.db.profile.units[frame.unitType].castBar.autoHide ) then
		LunaUF.Layout:SetBarVisibility(frame, "castBar", true)
	end

	cast.spellName = nil
	cast.fadeElapsed = FADE_TIME
	cast.fadeStart = FADE_TIME
	cast:SetScript("OnUpdate", fadeOnUpdate)
	cast:SetMinMaxValues(0, 1)
	cast:SetValue(1)
	cast:Show()
end

-- Cast interrupted
function Cast:EventInterruptCast(frame, event, unit, castID, spellID)
	local cast = frame.castBar.bar
	if( spellID and cast.spellID ~= spellID ) then return end
	
--	setBarColor(cast, LunaUF.db.profile.colors.interrupted.r, LunaUF.db.profile.colors.interrupted.g, LunaUF.db.profile.colors.interrupted.b)
	if( LunaUF.db.profile.units[frame.unitType].castBar.autoHide ) then
		LunaUF.Layout:SetBarVisibility(frame, "castBar", true)
	end

--	if( LunaUF.db.profile.units[frame.unitType].castBar.name.enabled ) then
--		cast.name:SetText(L["Interrupted"])
--	end

	cast.spellID = nil
	cast.fadeElapsed = FADE_TIME + 0.20
	cast.fadeStart = cast.fadeElapsed
	cast:SetScript("OnUpdate", fadeOnUpdate)
	cast:SetMinMaxValues(0, 1)
	cast:SetValue(1)
	cast:Show()
end

-- Cast succeeded
function Cast:EventCastSucceeded(frame, unit, spell)
	local cast = frame.castBar.bar
	if( not cast.isChannelled and cast.spellName == spell ) then
--		setBarColor(cast, LunaUF.db.profile.colors.finished.r, LunaUF.db.profile.colors.finished.g, LunaUF.db.profile.colors.finished.b)
	end
end

-- Interruptible status changed
function Cast:EventInterruptible(frame)
	local cast = frame.castBar.bar
	if( cast.isChannelled ) then
		setBarColor(cast, LunaUF.db.profile.colors.channel.r, LunaUF.db.profile.colors.channel.g, LunaUF.db.profile.colors.channel.b)
	else
		setBarColor(cast, LunaUF.db.profile.colors.cast.r, LunaUF.db.profile.colors.cast.g, LunaUF.db.profile.colors.cast.b)
	end
end

function Cast:EventUninterruptible(frame)
	--setBarColor(frame.castBar.bar, LunaUF.db.profile.colors.uninterruptible.r, LunaUF.db.profile.colors.uninterruptible.g, LunaUF.db.profile.colors.uninterruptible.b)
end

function Cast:UpdateDelay(frame, spell, displayName, icon, startTime, endTime)
	if( not spell or not frame.castBar.bar.startTime ) then return end
	local cast = frame.castBar.bar
	startTime = startTime / 1000
	endTime = endTime / 1000
	
	-- For a channel, delay is a negative value so using plus is fine here
	local delay = startTime - cast.startTime
	if( not cast.isChannelled ) then
		cast.endSeconds = cast.endSeconds + delay
		cast:SetMinMaxValues(0, cast.endSeconds)
	else
		cast.elapsed = cast.elapsed + delay
	end

	cast.pushback = cast.pushback + delay
	cast.lastUpdate = GetTime()
	cast.startTime = startTime
	cast.endTime = endTime
end

-- Update the actual bar
function Cast:UpdateCast(frame, unit, channelled, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID)
	if( not spell ) then return end
	local cast = frame.castBar.bar
	if( LunaUF.db.profile.units[frame.unitType].castBar.autoHide ) then
		LunaUF.Layout:SetBarVisibility(frame, "castBar", true)
	end

	-- Set casted spell
--	if( LunaUF.db.profile.units[frame.unitType].castBar.name.enabled ) then
--		cast.name:SetText(spell)
--		cast.name:SetAlpha(LunaUF.db.profile.bars.alpha)
--		cast.name:Show()
--	end
	
	-- Show cast time
--	if( cast.time.enabled ) then
--		cast.time:SetAlpha(1)
--		cast.time:Show()
--	end
	
	-- Set spell icon
	if( LunaUF.db.profile.units[frame.unitType].castBar.icon ~= "HIDE" ) then
		frame.castBar.icon:SetTexture(icon)
		frame.castBar.icon:Show()
	end
		
	-- Setup cast info
	cast.isChannelled = channelled
	cast.startTime = startTime / 1000
	cast.endTime = endTime / 1000
	cast.endSeconds = cast.endTime - cast.startTime
	cast.elapsed = cast.isChannelled and cast.endSeconds or 0
	cast.spellName = spell
	cast.spellID = spellID
	cast.pushback = 0
	cast.lastUpdate = cast.startTime
	cast:SetMinMaxValues(0, cast.endSeconds)
	cast:SetValue(cast.elapsed)
	cast:SetAlpha(1) --LunaUF.db.profile.bars.alpha)
	cast:Show()
	
	if( cast.isChannelled ) then
		cast:SetScript("OnUpdate", channelOnUpdate)
	else
		cast:SetScript("OnUpdate", castOnUpdate)
	end
	
	if( cast.isChannelled ) then
		setBarColor(cast, LunaUF.db.profile.colors.channel.r, LunaUF.db.profile.colors.channel.g, LunaUF.db.profile.colors.channel.b)
	else
		setBarColor(cast, LunaUF.db.profile.colors.cast.r, LunaUF.db.profile.colors.cast.g, LunaUF.db.profile.colors.cast.b)
	end
end

-- Trigger checks on fake cast
function Cast:UpdateFakeCast(self)
	local monitor = self.castBar.monitor
	monitor.endTime = nil
	monitor.notInterruptible = nil
	monitor.spellName = nil
	monitorFakeCast(monitor)
end