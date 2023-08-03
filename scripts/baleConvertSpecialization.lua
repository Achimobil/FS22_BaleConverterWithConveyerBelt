


BaleConvertItem = {}
local BaleConvertItem_mt = Class(BaleConvertItem, Object)


function BaleConvertItem.new(isServer, isClient, customMt)
	-- print(string.format("BaleConvertItem.new(%s,%s,%s)", isServer, isClient, customMt))
	local self = Object.new(isServer, isClient, customMt or BaleConvertItem_mt)
	
	self.timeSinceLastRun = 0;
	self.outputBlocked = false;

	return self
end


function BaleConvertItem:update(dt)
	BaleConvertItem:superClass().update(self, dt)
	-- print("BaleConvertItem:update("..dt..")")
	
	-- verzögerung
	self.timeSinceLastRun = self.timeSinceLastRun + dt;
	
	if self.baleInTrigger ~= nil then
		local fillTypeId = self.baleInTrigger.fillType
		local customEnvironment = nil;
		
		-- einen Ballen erstellen
		local baleXMLFilename = g_baleManager:getBaleXMLFilename(fillTypeId, false, nil, nil, 1.2, nil, customEnvironment)
		-- print("baleXMLFilename")
		-- print(baleXMLFilename)
		-- todo: Ausgabe an User wenn Ballen nicht angenommen wird
		
		if self.isServer and self.timeSinceLastRun > 1600 then
			self.timeSinceLastRun = 0;
			
			local baleObject = Bale.new(self.isServer, self.isClient)
			local x, y, z = getWorldTranslation(self.creationNode)
			local rx, ry, rz = getWorldRotation(self.creationNode)

			-- platz prüfen ob frei ist hier erforderlich
			self.outputBlocked = false;
			overlapBox(x, y, z, rx, ry, rz, 0.3, 0.2, 1, "outputAreaFreeCallback", self, 3212828671, true, false, true)
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
				
				if self.baleInTrigger.fillLevel <= 1 then
					-- nur wenn leer
					self.baleInTrigger:delete();
					self.baleInTrigger = nil 
				else
					self.baleInTrigger:setFillLevel(self.baleInTrigger.fillLevel - fillLevelForTargetBale)
				end
			end
		end
		
		
		-- loop as long as a bale is in the trigger
		if self.baleInTrigger ~= nil then
			self:raiseActive();
		end
		-- BaleConvertSpecialization.DebugTable("self", self);
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






BaleConvertSpecialization = {
    prerequisitesPresent = function (specializations)
        return true
    end,
    Version = "0.1.0.0",
    Name = "BaleConvertSpecialization",
}
print(g_currentModName .. " - init " .. BaleConvertSpecialization.Name .. "(Version: " .. BaleConvertSpecialization.Version .. ")");

function BaleConvertSpecialization.DebugTable(text, myTable)
	print(text)
	DebugUtil.printTableRecursively(myTable,"_",0,2)
end

function BaleConvertSpecialization.registerOverwrittenFunctions(placeableType)
	-- SpecializationUtil.registerOverwrittenFunction(placeableType, "update", BaleConvertSpecialization.update)
end

function BaleConvertSpecialization.registerFunctions(placeableType)
	SpecializationUtil.registerFunction(placeableType, "inputTriggerCallback", BaleConvertSpecialization.inputTriggerCallback)
end

function BaleConvertSpecialization.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", BaleConvertSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onDelete", BaleConvertSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", BaleConvertSpecialization)
end

function BaleConvertSpecialization.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("BaleMove")
    
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".baleConvert#triggerNode", "Trigger node to detect bales whch should be converted")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".baleConvert#creationNode", "Node where the 120er bale will be created")
    
    schema:setXMLSpecializationType()
end

function BaleConvertSpecialization:onLoad(savegame)

	-- BaleConvertSpecialization.DebugTable("self", self);
    local xmlFile = self.xmlFile
	
    self.spec_baleConvert = {};
    local spec =  self.spec_baleConvert;
	spec.baleConvertItem = BaleConvertItem.new(self.isServer, self.isClient)
	
	local key = "placeable.baleConvert"
	
	spec.baleConvertItem.triggerNodeId = xmlFile:getValue(key .. "#triggerNode", nil, self.components, self.i3dMappings);
	addTrigger(spec.baleConvertItem.triggerNodeId, "inputTriggerCallback", self);
	
	spec.baleConvertItem.creationNode = xmlFile:getValue(key .. "#creationNode", nil, self.components, self.i3dMappings);
	
end

function BaleConvertSpecialization:inputTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    local spec =  self.spec_baleConvert;
-- print("inputTriggerCallback")
	local bale = g_currentMission.nodeToObject[otherId];

-- BaleConvertSpecialization.DebugTable("spec", spec)
	-- only one bale can be in the trigger. Overwrite it simply
	if bale ~= nil and bale:isa(Bale) then
		if onEnter then
			if spec.baleConvertItem.baleInTrigger == nil then
				spec.baleConvertItem.baleInTrigger = bale;
				spec.baleConvertItem:raiseActive();
			end
		elseif onLeave then
			if spec.baleConvertItem.baleInTrigger == bale then
				spec.baleConvertItem.baleInTrigger = nil;
				spec.baleConvertItem:raiseActive();
			end
		end
	end
end

function BaleConvertSpecialization:onFinalizePlacement()
print("BaleConvertSpecialization:onFinalizePlacement()")
	local spec =  self.spec_baleConvert;
    -- for _, baleMoveItem in pairs(spec.baleMoveItems) do
		spec.baleConvertItem:register(true)
	-- end
	
end

function BaleConvertSpecialization:onDelete()
	local spec =  self.spec_baleConvert;
    -- for _, baleMoveItem in pairs(spec.baleMoveItems) do
		removeTrigger(spec.baleConvertItem.triggerNodeId)
	-- end
end