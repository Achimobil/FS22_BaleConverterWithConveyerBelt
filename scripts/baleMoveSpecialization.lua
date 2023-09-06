--[[
Copyright (C) Achimobil, ab 2023

Author: Achimobil
Date: 06.09.2023
Version: 0.1.0.0

Important:
No changes are to be made to this script without written permission from Achimobil.

Wichtig
An diesem Skript dürfen ohne schrifltiche Genehmigung von Achimobil keine Änderungen vorgenommen werden.
]]

-- ObjectIds.BaleMoveItem = nextObjectId()
BaleMoveItem = {}
local BaleMoveItem_mt = Class(BaleMoveItem, Object)

function BaleMoveItem.new(isServer, isClient, customMt)
	-- print(string.format("BaleMoveItem.new(%s,%s,%s)", isServer, isClient, customMt))
	local self = Object.new(isServer, isClient, customMt or BaleMoveItem_mt)
	self.onBeltTriggerId = nil
	self.balesOnBelt = {}
	self.jointToInfo = {}
	self.speed = 3
	self.motorSpeed = -10
	self.baleInStopTrigger = {}
	self.baleInStopTriggerCount = 0

	return self
end

function BaleMoveItem:update(dt)
	BaleMoveItem:superClass().update(self, dt)
	-- print("BaleMoveItem:update(dt)")
	
	-- wenn stop trigger was erfasst hat, nichts weiteres hier machen
	if self.baleInStopTriggerCount ~= 0 then
		return;
	end
	
	-- hier jetzt den ballen bewegen, wenn nicht attached oder so
	if self.isServer then
		for bale, info in pairs(self.balesOnBelt) do
			if bale.mountObject == nil and bale.dynamicMountObject == nil then
				if self.stop == true then return end;
				
				if info.jointIndex == 0 then
					self:addBaleJoint(info)
				end

				local x, y, z = getTranslation(info.jointNode)
				local xDir = -1
				local zDir = 0

				if info.xDirection ~= 0 then
					zDir = 0
					xDir = info.xDirection
				end

				local yDir = MathUtil.clamp(-y / 0.05, -1, 1)
				local speed = self.speed * dt / 1000
				z = z + zDir * speed
				y = y + yDir * speed
				x = x + xDir * speed

				setTranslation(info.jointNode, x, y, z)
				setJointFrame(info.jointIndex, 0, info.jointNode)
			elseif info.jointIndex ~= 0 then
				self:removeBaleJoint(info)
			end
		end
	end
	
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
end

function BaleMoveItem:addBaleJoint(baleInfo)
	if baleInfo.jointIndex == 0 then
		local bale = baleInfo.bale
		local jointNode = createTransformGroup("jointNode")

		link(self.beltJointBaseNode, jointNode)

		local x, y, z = localToWorld(bale.nodeId, getCenterOfMass(bale.nodeId))

		setWorldTranslation(jointNode, x, y, z)
		setCollisionMask(bale.nodeId, 18)

		local constr = JointConstructor.new()

		constr:setActors(self.beltAnchorNode, bale.nodeId)
		constr:setJointTransforms(jointNode, jointNode)
		constr:setTranslationLimit(1, true, -0.2, 0.2)

		local angleY = math.rad(5)

		constr:setRotationLimit(1, -angleY, angleY)

		local forceLimit = 250 * getMass(bale.nodeId)

		constr:setBreakable(forceLimit, forceLimit)
		constr:setEnableCollision(true)

		baleInfo.jointIndex = constr:finalize()
		baleInfo.jointNode = jointNode
		bale.isOnBelt = true
		self.jointToInfo[baleInfo.jointIndex] = baleInfo

		addJointBreakReport(baleInfo.jointIndex, "onDynamicMountJointBreak", self)
	end
end


function BaleMoveItem:onDynamicMountJointBreak(jointIndex, breakingImpulse)
	local baleInfo = self.jointToInfo[jointIndex]

	self:removeBaleJoint(baleInfo)
end

function BaleMoveItem:removeBaleJoint(baleInfo)
	if baleInfo.jointIndex ~= 0 then
		removeJoint(baleInfo.jointIndex)
		delete(baleInfo.jointNode)

		self.jointToInfo[baleInfo.jointIndex] = nil
		baleInfo.jointIndex = 0
		baleInfo.jointNode = nil
		baleInfo.bale.isOnBelt = false

		if baleInfo.bale.nodeId ~= 0 then
			setCollisionMask(baleInfo.bale.nodeId, 16781314)
		end
	end
end










BaleMoveSpecialization = {
    prerequisitesPresent = function (specializations)
        return true
    end,
    Version = "0.1.0.0",
    Name = "BaleMoveSpecialization",
}
print(g_currentModName .. " - init " .. BaleMoveSpecialization.Name .. "(Version: " .. BaleMoveSpecialization.Version .. ")");

function BaleMoveSpecialization.DebugTable(text, myTable)
	print(text)
	DebugUtil.printTableRecursively(myTable,"_",0,2)
end

function BaleMoveSpecialization.registerOverwrittenFunctions(placeableType)
	-- SpecializationUtil.registerOverwrittenFunction(placeableType, "update", BaleMoveSpecialization.update)
end

function BaleMoveSpecialization.registerFunctions(placeableType)
	SpecializationUtil.registerFunction(placeableType, "onBeltTriggerCallback", BaleMoveSpecialization.onBeltTriggerCallback)
	SpecializationUtil.registerFunction(placeableType, "onStopTriggerCallback", BaleMoveSpecialization.onStopTriggerCallback)
	SpecializationUtil.registerFunction(placeableType, "onDeleteBale", BaleMoveSpecialization.onDeleteBale)
	SpecializationUtil.registerFunction(placeableType, "onDeleteBaleFromStop", BaleMoveSpecialization.onDeleteBaleFromStop)
end

function BaleMoveSpecialization.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", BaleMoveSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onDelete", BaleMoveSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", BaleMoveSpecialization)
end

function BaleMoveSpecialization.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("BaleMove")
    
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".baleMoves.baleMove(?)#onBeltTrigger", "Trigger node to detect bales whch should be moved")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".baleMoves.baleMove(?)#jointBaseNode", "Base node for joint between belt and bale")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".baleMoves.baleMove(?)#anchorNode", "target note for movement to")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".baleMoves.baleMove(?)#stopTrigger", "Trigger to Stop movement at the end ob the belt")
	
	schema:register(XMLValueType.NODE_INDEX, basePath .. ".baleMoves.baleMove(?).uvAnimations.uvAnimation(?)#node", "")
	schema:register(XMLValueType.INT, basePath .. ".baleMoves.baleMove(?).uvAnimations.uvAnimation(?)#parameter", "")
	schema:register(XMLValueType.FLOAT, basePath .. ".baleMoves.baleMove(?).uvAnimations.uvAnimation(?)#to", "")
	schema:register(XMLValueType.FLOAT, basePath .. ".baleMoves.baleMove(?).uvAnimations.uvAnimation(?)#speed", "")
    
    schema:setXMLSpecializationType()
end

function BaleMoveSpecialization:onLoad(savegame)

	-- BaleMoveSpecialization.DebugTable("self", self);
	
    self.spec_baleMove = {};
    local spec =  self.spec_baleMove;
	spec.baleMoveItems = {}
	spec.stopTriggerToBeltTrigger = {}
	
	
    local xmlFile = self.xmlFile
	
	xmlFile:iterate("placeable.baleMoves.baleMove", function (_, key)
		local baleMoveItem = BaleMoveItem.new(self.isServer, self.isClient)
		baleMoveItem.onBeltTriggerId = xmlFile:getValue(key .. "#onBeltTrigger", nil, self.components, self.i3dMappings);
		baleMoveItem.beltJointBaseNode = xmlFile:getValue(key .. "#jointBaseNode", nil, self.components, self.i3dMappings)
		baleMoveItem.beltAnchorNode = xmlFile:getValue(key .. "#anchorNode", nil, self.components, self.i3dMappings)
		baleMoveItem.stopTriggerId = xmlFile:getValue(key .. "#stopTrigger", nil, self.components, self.i3dMappings)
		
		addTrigger(baleMoveItem.onBeltTriggerId, "onBeltTriggerCallback", self);
		addTrigger(baleMoveItem.stopTriggerId, "onStopTriggerCallback", self);
		
		baleMoveItem.uvAnimations = {}

		xmlFile:iterate(key .. ".uvAnimations.uvAnimation", function (_, key)
			local animNode = xmlFile:getValue(key .. "#node", nil, self.components, self.i3dMappings)
			local to = xmlFile:getValue(key .. "#to")
			local parameter = xmlFile:getValue(key .. "#parameter")
			local speed = xmlFile:getValue(key .. "#speed")

			table.insert(baleMoveItem.uvAnimations, {
				current = 0,
				node = animNode,
				to = to,
				parameter = parameter,
				speed = speed
			})
		end)

		spec.baleMoveItems[baleMoveItem.onBeltTriggerId] = baleMoveItem;
		spec.stopTriggerToBeltTrigger[baleMoveItem.stopTriggerId] = baleMoveItem.onBeltTriggerId
	end)
end

function BaleMoveSpecialization:onBeltTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    local spec =  self.spec_baleMove;
	local currentBaleMoveItem = spec.baleMoveItems[triggerId];
	-- print("onBeltTriggerCallback")
	
	local bale = g_currentMission.nodeToObject[otherId];


	if bale ~= nil and bale:isa(Bale) then
		if onEnter then
			if currentBaleMoveItem.balesOnBelt[bale] == nil then
				local info = {
					jointIndex = 0,
					bale = bale,
					xDirection = 0
				}
				currentBaleMoveItem.balesOnBelt[bale] = info
				if bale.addDeleteListener ~= nil then
					bale:addDeleteListener(self, "onDeleteBale")
				end
				currentBaleMoveItem:raiseActive();
			end
		elseif onLeave then
			local info = currentBaleMoveItem.balesOnBelt[bale]

			if info ~= nil then
				currentBaleMoveItem:removeBaleJoint(info)

				currentBaleMoveItem.balesOnBelt[bale] = nil
				if bale.removeDeleteListener ~= nil then
					bale:removeDeleteListener(self, "onDeleteBale")
				end
				currentBaleMoveItem:raiseActive();
			end
		end
	end
	
end

function BaleMoveSpecialization:onStopTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    local spec =  self.spec_baleMove;
	local currentBaleMoveItem = spec.baleMoveItems[spec.stopTriggerToBeltTrigger[triggerId]];
	-- print("onStopTriggerCallback")
	
	local bale = g_currentMission.nodeToObject[otherId];

	-- put the bale in the stop list to stop the moving until it is free again
	if bale ~= nil and bale:isa(Bale) then
		if onEnter then
			if currentBaleMoveItem.baleInStopTrigger[bale] == nil then
				currentBaleMoveItem.baleInStopTrigger[bale] = true;
				currentBaleMoveItem.baleInStopTriggerCount = currentBaleMoveItem.baleInStopTriggerCount + 1;
				if bale.addDeleteListener ~= nil then
					bale:addDeleteListener(self, "onDeleteBaleFromStop")
				end
			end
		elseif onLeave then
			if currentBaleMoveItem.baleInStopTrigger[bale] ~= nil then
				currentBaleMoveItem.baleInStopTrigger[bale] = nil
				currentBaleMoveItem.baleInStopTriggerCount = currentBaleMoveItem.baleInStopTriggerCount - 1;
				if bale.removeDeleteListener ~= nil then
					bale:removeDeleteListener(self, "onDeleteBaleFromStop")
				end
			end
		end
	end
	
end

function BaleMoveSpecialization:onFinalizePlacement()
-- print("BaleMoveSpecialization:onFinalizePlacement()")
	local spec =  self.spec_baleMove;
    for _, baleMoveItem in pairs(spec.baleMoveItems) do
		baleMoveItem:register(true)
	end
	
end

function BaleMoveSpecialization:onDelete()
	local spec =  self.spec_baleMove;
    for _, baleMoveItem in pairs(spec.baleMoveItems) do
		baleMoveItem.stop = true;
		removeTrigger(baleMoveItem.onBeltTriggerId)
		removeTrigger(baleMoveItem.stopTriggerId)
	end
end

function BaleMoveSpecialization:onDeleteBale(object)
	local spec =  self.spec_baleMove;

    for _, baleMoveItem in pairs(spec.baleMoveItems) do
		if baleMoveItem.balesOnBelt[object] ~= nil then
			baleMoveItem.balesOnBelt[object] = nil
		end
	end
end

function BaleMoveSpecialization:onDeleteBaleFromStop(object)
	local spec =  self.spec_baleMove;

    for _, baleMoveItem in pairs(spec.baleMoveItems) do
		if baleMoveItem.baleInStopTrigger[object] ~= nil then
			baleMoveItem.balesOnBelt[object] = nil
			baleMoveItem.baleInStopTriggerCount = baleMoveItem.baleInStopTriggerCount - 1;
		end
	end
end