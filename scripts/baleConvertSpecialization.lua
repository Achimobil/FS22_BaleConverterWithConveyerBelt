--[[
Copyright (C) Achimobil, ab 2023

Author: Achimobil
Date: 22.11.2023
Version: 0.2.0.0

Important:
No changes are to be made to this script without written permission from Achimobil.

Wichtig
An diesem Skript dürfen ohne schrifltiche Genehmigung von Achimobil keine Änderungen vorgenommen werden.
]]

BaleConvertItem = {}
local BaleConvertItem_mt = Class(BaleConvertItem, Object)

function BaleConvertItem.new(isServer, isClient, customMt, parent)
	-- print(string.format("BaleConvertItem.new(%s,%s,%s,%s)", isServer, isClient, customMt, parent))
	local self = setmetatable({}, customMt or BaleConvertItem_mt)
	self.isServer = isServer;
	self.isClient = isClient;
	self.parent = parent;

	self.timeSinceLastRun = 0;
	self.outputBlocked = false;
	self.motorSpeed = 10;
	self.soundIsOn = false;
	self.isTurnedOn = false;

	return self
end

function BaleConvertItem:update(dt)
	BaleConvertItem:superClass().update(self, dt)
	-- print(string.format("BaleConvertItem.update(%s) - isServer:%s isClient: %s", dt, self.isServer, self.isClient))
	
	-- verzögerung
	self.timeSinceLastRun = self.timeSinceLastRun + dt;
	
	if self.baleInTrigger ~= nil then
		local fillTypeId = self.baleInTrigger.fillType
		local customEnvironment = nil;
		
		-- einen Ballen erstellen
		local baleXMLFilename = g_baleManager:getBaleXMLFilename(fillTypeId, false, nil, nil, 1.2, nil, customEnvironment)
		
		if self.isServer then 
			if self.timeSinceLastRun > 500 then
				self.timeSinceLastRun = 0;
				
				local baleObject = Bale.new(self.isServer, self.isClient)
				local x, y, z = getWorldTranslation(self.creationNode)
				local rx, ry, rz = getWorldRotation(self.creationNode)

				-- platz prüfen ob frei ist hier erforderlich
				self.outputBlocked = false;
				overlapBox(x, y, z, rx, ry, rz, 0.225, 0.175, 0.6, "outputAreaFreeCallback", self, 3212828671, true, false, true)
				if self.outputBlocked == false and baleObject:loadFromConfigXML(baleXMLFilename, x, y, z, rx, ry, rz) then
				
					-- wie viel passt in den 120er ballen?
					local maxInTargetBale
					for _, baleFillType in pairs(baleObject.fillTypes) do
						if baleFillType.fillTypeIndex == fillTypeId then
							maxInTargetBale = baleFillType.capacity;
						end
					end
					
					local availableFillLevel = self.baleInTrigger.fillLevel;
					local fillLevelForTargetBale = math.min(availableFillLevel, maxInTargetBale);
				
					baleObject:setFillType(fillTypeId)
					baleObject:setFillLevel(fillLevelForTargetBale)
					baleObject:setOwnerFarmId(self.baleInTrigger.ownerFarmId, true)
					baleObject:register()
					
					
					-- BaleConvertSpecialization.DebugTable("baleObject", baleObject);
					
					if (self.baleInTrigger.fillLevel - fillLevelForTargetBale) <= 1 then
						-- nur wenn leer
						self.baleInTrigger:delete();
						self.baleInTrigger = nil 
					else
						self.baleInTrigger:setFillLevel(self.baleInTrigger.fillLevel - fillLevelForTargetBale)
					end
				end
			end
		end
		
		if self.isClient then 
			-- animation und sound nur auf client
			-- Animation läuft solange wie ein ballen im Trigger ist
			for _, animation in ipairs(self.uvAnimations) do
				if self.stop == true then return end;
				animation.current = (animation.current + dt * self.motorSpeed * 0.001 * animation.to * animation.speed) % animation.to
				local x, y, z, w = getShaderParameter(animation.node, "offsetUV")

				if animation.parameter == 0 then
					setShaderParameter(animation.node, "offsetUV", animation.current, y, z, w, false)
				elseif animation.parameter == 2 then
					setShaderParameter(animation.node, "offsetUV", x, y, animation.current, w, false)
				end
			end
			
			-- loop as long as a bale is in the trigger
			if self.baleInTrigger ~= nil then
				self:PlaySound(true);
				self.parent:raiseActive();
			else
				self:PlaySound(false);
			end
		end
	else
		if self.isClient then 
			-- auf client sound stoppen
			self:PlaySound(false);
		end
	end
end

function BaleConvertItem:SetTurnOn(isTurnedOn, noEventSend)
	-- print(string.format("BaleConvertItem.SetTurnOn(%s, %s)", isTurnedOn, noEventSend))
	local spec = self.spec_baleConvert;
	
	
	if self.isTurnedOn ~= isTurnedOn then
		-- bei status änderung aktivieren, rest macht dann die update
		self:raiseActive()
	end
end

function BaleConvertItem:outputAreaFreeCallback(transformId)
	if transformId ~= 0 and getHasClassId(transformId, ClassIds.SHAPE) then
		local spec = self.spec_aPalletAutoLoader

		local object = g_currentMission:getNodeObject(transformId)
		if object ~= nil and object ~= self then
			self.outputBlocked = true
		end
	end

	return true
end


function BaleConvertItem:PlaySound(animationRunning)
	-- print(string.format("BaleConvertItem:PlaySound baleInTrigger:%s shouldRun:%s IsRuning:%s", self.baleInTrigger ~= nil, animationRunning, self.soundIsOn))
	self.isTurnedOn = animationRunning;
	if self.isClient then 
		-- sound hier einstellen, damit das unten weiterhin einfach ein return machen kann, wenn der rest weg fällt
		if animationRunning and not self.soundIsOn then
			-- war aus und läuft gerade an
			-- print("BaleConvertItem PlaySound on")
			self.soundIsOn = true;
			g_soundManager:stopSamples(self.samples)
			g_soundManager:playSample(self.samples.start)
			g_soundManager:playSample(self.samples.work, 0, self.samples.start)
		elseif not animationRunning and self.soundIsOn then
			-- ist an, aber jetzt geht er aus
			-- print("BaleConvertItem PlaySound off")
			self.soundIsOn = false;
			g_soundManager:stopSamples(self.samples)
			g_soundManager:playSample(self.samples.stop)
		end
	end
end


BaleConvertSpecialization = {
    prerequisitesPresent = function (specializations)
        return true
    end,
    Version = "0.2.0.0",
    Name = "BaleConvertSpecialization",
}
print(g_currentModName .. " - init " .. BaleConvertSpecialization.Name .. "(Version: " .. BaleConvertSpecialization.Version .. ")");

function BaleConvertSpecialization.DebugTable(text, myTable)
	print(text)
	DebugUtil.printTableRecursively(myTable,"_",0,2)
end

function BaleConvertSpecialization.registerFunctions(placeableType)
	SpecializationUtil.registerFunction(placeableType, "inputTriggerCallback", BaleConvertSpecialization.inputTriggerCallback)
end

function BaleConvertSpecialization.registerEventListeners(placeableType)
	-- print("BaleConvertSpecialization:registerEventListeners(placeableType)")
    SpecializationUtil.registerEventListener(placeableType, "onLoad", BaleConvertSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onDelete", BaleConvertSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onUpdate", BaleConvertSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onReadStream", BaleConvertSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onWriteStream", BaleConvertSpecialization)
end

function BaleConvertSpecialization.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("BaleMove")
    
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".baleConvert#triggerNode", "Trigger node to detect bales whch should be converted")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".baleConvert#creationNode", "Node where the 120er bale will be created")
	
	schema:register(XMLValueType.NODE_INDEX, basePath .. ".baleConvert.uvAnimations.uvAnimation(?)#node", "")
	schema:register(XMLValueType.INT, basePath .. ".baleConvert.uvAnimations.uvAnimation(?)#parameter", "")
	schema:register(XMLValueType.FLOAT, basePath .. ".baleConvert.uvAnimations.uvAnimation(?)#to", "")
	schema:register(XMLValueType.FLOAT, basePath .. ".baleConvert.uvAnimations.uvAnimation(?)#speed", "")
    
	SoundManager.registerSampleXMLPaths(schema, basePath .. ".baleConvert.sounds", "start")
	SoundManager.registerSampleXMLPaths(schema, basePath .. ".baleConvert.sounds", "work")
	SoundManager.registerSampleXMLPaths(schema, basePath .. ".baleConvert.sounds", "stop")
    
    schema:setXMLSpecializationType()
end

function BaleConvertSpecialization:onLoad(savegame)
	-- print("BaleConvertSpecialization:onLoad(savegame)")

	-- BaleConvertSpecialization.DebugTable("self", self);
    local xmlFile = self.xmlFile
	
    self.spec_baleConvert = {};
    local spec =  self.spec_baleConvert;
	spec.baleConvertItem = BaleConvertItem.new(self.isServer, self.isClient, nil, self)
	
	local key = "placeable.baleConvert"
	
	spec.baleConvertItem.triggerNodeId = xmlFile:getValue(key .. "#triggerNode", nil, self.components, self.i3dMappings);
	addTrigger(spec.baleConvertItem.triggerNodeId, "inputTriggerCallback", self);
	
	spec.baleConvertItem.creationNode = xmlFile:getValue(key .. "#creationNode", nil, self.components, self.i3dMappings);
		
	spec.baleConvertItem.uvAnimations = {}

	xmlFile:iterate(key .. ".uvAnimations.uvAnimation", function (_, key)
		local animNode = xmlFile:getValue(key .. "#node", nil, self.components, self.i3dMappings)
		local to = xmlFile:getValue(key .. "#to")
		local parameter = xmlFile:getValue(key .. "#parameter")
		local speed = xmlFile:getValue(key .. "#speed")

		table.insert(spec.baleConvertItem.uvAnimations, {
			current = 0,
			node = animNode,
			to = to,
			parameter = parameter,
			speed = speed
		})
	end)
		
	spec.baleConvertItem.samples = {
		start = g_soundManager:loadSampleFromXML(xmlFile, key .. ".sounds", "start", self.modDirectory, self.components, 1, AudioGroup.ENVIRONMENT, self.i3dMappings, self),
		stop = g_soundManager:loadSampleFromXML(xmlFile, key .. ".sounds", "stop", self.modDirectory, self.components, 1, AudioGroup.ENVIRONMENT, self.i3dMappings, self),
		work = g_soundManager:loadSampleFromXML(xmlFile, key .. ".sounds", "work", self.modDirectory, self.components, 0, AudioGroup.ENVIRONMENT, self.i3dMappings, self)
	}
	
end

function BaleConvertSpecialization:inputTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
	-- print("inputTriggerCallback")
    local spec =  self.spec_baleConvert;
	-- BaleConvertSpecialization.DebugTable("spec", spec)
	local bale = g_currentMission.nodeToObject[otherId];

	-- only one bale can be in the trigger. Overwrite it simply
	if bale ~= nil and bale:isa(Bale) then
		if onEnter then
			if spec.baleConvertItem.baleInTrigger == nil then
				spec.baleConvertItem.baleInTrigger = bale;
				self:raiseActive();
			end
		elseif onLeave then
			if spec.baleConvertItem.baleInTrigger == bale then
				spec.baleConvertItem.baleInTrigger = nil;
				self:raiseActive();
			end
		end
	end
end

function BaleConvertSpecialization:onDelete()
	local spec =  self.spec_baleConvert;
	spec.baleConvertItem.stop = true;
	removeTrigger(spec.baleConvertItem.triggerNodeId)
end

function BaleConvertSpecialization:onUpdate(dt)
	-- print("BaleConvertSpecialization:onUpdate()")
	local spec =  self.spec_baleConvert;
	spec.baleConvertItem:update(dt)
end

function BaleConvertSpecialization:onWriteStream(streamId, connection)
	-- print("BaleConvertSpecialization:onWriteStream()")
	local spec = self.spec_baleConvert

	streamWriteBool(streamId, spec.baleConvertItem.isTurnedOn)
end

function BaleConvertSpecialization:onReadStream(streamId, connection)
	-- print("BaleConvertSpecialization:onReadStream()")
	local isTurnedOn = streamReadBool(streamId)

	local spec = self.spec_baleConvert;
	spec.baleConvertItem:SetTurnOn(isTurnedOn);
end