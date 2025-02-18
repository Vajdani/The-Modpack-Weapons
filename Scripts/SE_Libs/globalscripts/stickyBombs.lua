--[[
	Copyright (c) 2019 Brent Batch
]]--

local reload = stickyBomb and stickyBomb.client_reload -- gets old already existing scriptclass from before reload if it exists. (exec 'reload()' at the end of this script tho)


stickyBomb = {} -- MANAGER
stickyBomb.ammo = {} -- { [spawnedscript.shape.id] = { {type,target,detonationTime,pointLocal,normalLocal},{},{} },      }
stickyBomb.server_queued = {}

local someFuckingNumber = 0 -- 'uuid replacement' , scrap uuid implementation sucks

function stickyBomb.server_onCreate(self, ...)
	--print('stickyBomb.client_onCreate')
end

function stickyBomb.server_onFixedUpdate(self, dt)
	--print('stickyBomb.server_onFixedUpdate', self.server_queued)
	for key, queued in pairs(self.server_queued) do --print('server_queued')
		local shapeId, position, velocity, detonationTime, capacity, explodeOld = queued[1], queued[2], queued[3], queued[4], queued[5], queued[6]
		if self.ammo[shapeId] then
			local i = 0
			local bombIds = {} --
			for k, bomb in pairs(self.ammo[shapeId]) do
				if not bomb.done then
					i = i+1
					table.insert(bombIds, k)
				end
			end
			table.sort(bombIds) -- make it so oldest are first
			local cap = math.max(0,capacity - 1) -- if capacity >0 then it's about to spawn one, gotta remove an old one then.
			if i > cap then
				--print('over capacity of', capacity, 'has:', i, 'bombs:', bombIds)
				local illegalbombs = {}
				local removebombs = i - cap
				for k, id in pairs(bombIds) do
					if k > removebombs then break end
					table.insert(illegalbombs, id)
					self.ammo[shapeId][id].done = true
					if explodeOld then
						local bomb = self.ammo[shapeId][id]
						sm.physics.explode( bomb.position + bomb.velocity * dt,  6, 0.13, 0.5, 1, "PropaneTank - ExplosionSmall")
					end
				end
				--print('removing:', illegalbombs)
				self.network:sendToClients("client_killBombs", {shapeId, illegalbombs})
			end
		end
		if capacity > 0 then
			someFuckingNumber = someFuckingNumber + 1
			--print('creating bomb id:',someFuckingNumber)
			self.network:sendToClients("client_createBomb", {shapeId, someFuckingNumber, position, velocity, detonationTime, sm.physics.getGravity()/10})
		end
		self.server_queued[key] = nil
	end

	for shapeId, bombs in pairs(self.ammo) do
		for id, bomb in pairs(bombs) do
			if bomb.detonationTime < dt and not bomb.done then
									--position, level, destructionRadius, impulseRadius, magnitude
				sm.physics.explode( bomb.position + bomb.velocity * dt,  6, 0.13, 0.5, 1, "PropaneTank - ExplosionSmall")
				bomb.done = true
			end
			if not bomb.type then -- sad bomb has no target, raycast for one
				local hit, result = sm.physics.raycast( bomb.position, bomb.position + bomb.velocity * dt * 1.1)
				if hit then
					local type = result.type
					local target;
					local position = result.pointWorld + result.normalWorld/8
					local velocity = sm.vec3.new(0,0,0)
					local pointLocal;
					local normalLocal;
					if type == "body" then
						target = result:getShape()
						velocity = target.velocity
						pointLocal = target:transformPoint(result.pointWorld + result.normalWorld/16)
						normalLocal = result.normalLocal
					end
					if type == "character" then 
						target = result:getCharacter()
						velocity = target.velocity
						local direction = target.direction   direction.z = 0   direction = sm.vec3.normalize(direction)
						local angle = math.atan2(direction.x, direction.y)
						pointLocal = sm.vec3.rotateZ((result.pointWorld - target.worldPosition), angle)
						normalLocal = sm.vec3.rotateZ(result.normalLocal, angle)
					end

					self.network:sendToClients("client_setBombTarget", {shapeId, id, type, position, velocity, target, pointLocal, normalLocal, bomb.detonationTime, bomb.grav})
				end
			end
		end
	end
end

--client: 

function stickyBomb.client_createBomb(self, data)
	local shapeId, id, position, velocity, detonationTime, gravity = unpack(data)
	local bomb = {effect = sm.effect.createEffect("StickyBomb"), position = position, velocity = velocity, detonationTime = detonationTime, grav = gravity}
	bomb.effect:setPosition( position )
	--bomb.effect:setVelocity( velocity)
	bomb.effect:start()
	if not self.ammo[shapeId] then self.ammo[shapeId] = {} end
	self.ammo[shapeId][id] = bomb
end


function stickyBomb.client_onCreate(self, ...)
	print('stickyBomb.client_onCreate')
	--ask server for existing projectiles ? 
end

function stickyBomb.client_setBombTarget(self, data)
	local shapeId, id, type, position, velocity, target, pointLocal, normalLocal, detonationTime, gravity = unpack(data)
	local bombs = self.ammo[shapeId]
	if not bombs then self.ammo[shapeId] = {} end
	local bomb = self.ammo[shapeId][id]
	if not bomb then -- this client joined and this bomb doesn't exist yet, create it cuz its possible :)
		self:client_createBomb({shapeId, id, position, velocity, detonationTime, gravity})
		bomb = self.ammo[shapeId][id]
	end
	bomb.type = type
	bomb.position = position
	bomb.velocity = velocity
	bomb.effect:setPosition( position )
	bomb.effect:setVelocity( velocity)
	bomb.target = target
	bomb.pointLocal = pointLocal
	bomb.normalLocal = normalLocal
end

function stickyBomb.client_killBombs(self, data)
	local shapeId, illegalbombs = unpack(data)
	local bombs = self.ammo[shapeId]
	if not bombs then return end
	for _, k in pairs(illegalbombs) do
		--print('clearing bomb', k)
		self.ammo[shapeId][k].effect:stop()
		self.ammo[shapeId][k] = nil
	end
end


function stickyBomb.client_onFixedUpdate(self,dt)
	--print('stickyBomb.client_onFixedUpdate')
	for shapeId, bombs in pairs(self.ammo) do
		for id, bomb in pairs(bombs) do
			-- flight path:
			if bomb.type then
				if bomb.type == "body" then
					if sm.exists(bomb.target) then
						bomb.velocity = bomb.target.velocity
						bomb.position = bomb.target.worldPosition + bomb.target.worldRotation * bomb.pointLocal
						bomb.effect:setRotation( bomb.target.worldRotation * sm.vec3.getRotation(sm.vec3.new(0,0,1), bomb.normalLocal))
					else
						bomb.type, bomb.target = nil, nil -- drops bomb
					end
				elseif bomb.type == "character" then
					if sm.exists(bomb.target) then -- TODO: pointLocal
						--bomb.velocity = bomb.target.velocity
						--bomb.position = bomb.target.worldPosition + bomb.target.velocity * dt

						local direction = bomb.target.direction   direction.z = 0   direction = sm.vec3.normalize(direction)
						local angleDirection = math.atan2(direction.x, direction.y)
						local rotatedNormal = sm.vec3.rotateZ(bomb.normalLocal, -angleDirection)
						local angleNormal = math.atan2(rotatedNormal.x, rotatedNormal.y)
						local normalRotatedToY = sm.vec3.rotateZ(rotatedNormal, angleNormal)
						local rot = sm.vec3.getRotation(-normalRotatedToY, rotatedNormal)* sm.vec3.getRotation(sm.vec3.new( 0,0,-1 ), normalRotatedToY) * sm.vec3.getRotation(sm.vec3.new( 0,1,0 ), sm.vec3.new( 1,0,0 )) 

						bomb.effect:setRotation( rot )
						bomb.position = sm.vec3.rotateZ(bomb.pointLocal, -angleDirection) + bomb.target.worldPosition
						bomb.velocity = (bomb.position - (bomb.oldpos or bomb.position))/dt
						bomb.oldpos = bomb.position
					else
						bomb.type, bomb.target = nil, nil -- drops bomb
					end
				end
				bomb.detonationTime = bomb.detonationTime - dt
			else
				bomb.velocity = bomb.velocity*0.975 - sm.vec3.new(0,0,bomb.grav*dt*10) 
				bomb.position = bomb.position + bomb.velocity* dt
			end

			-- animate bullet:
			--if math.random(5) == 1 then -- bullets are 'jumpy' if position is set too regulary
				bomb.effect:setPosition(bomb.position)
			--end
			--bomb.effect:setVelocity(bomb.velocity)

			if bomb.detonationTime < 0 then
				bomb.effect:setPosition(sm.vec3.new(0,0,1000000))
				bomb.effect:stop()
				self.ammo[shapeId][id] = nil
			end
		end
	end
end

function stickyBomb.client_onRefresh(self)
	--print('hostblock.client_onRefresh')
end

function stickyBomb.onDestroy(self)
	print('stickyBomb onDestroy')
	for shapeId, bombs in pairs(self.ammo) do
		for id, bomb in pairs(bombs) do
			bomb.effect:stop()
			self.ammo[shapeId][k] = nil
		end
	end
end


-- API for scripted parts:
-- scripted parts will perform the following functions to initialize the above globalscript


function stickyBomb.server_spawnBomb(shapeId, pos, velocity, detonationTime, capacity) -- can be called from server or from client, it's best to call from server tho
	if not sm.isHost then return end
	assert(shapeId and pos and velocity and detonationTime and capacity, "stickyBomb.server_spawnBomb: please fill in all parameters: shapeId, pos, velocity, detonationTime, capacity")

	table.insert(stickyBomb.server_queued, {shapeId, pos, velocity, detonationTime, capacity})
end

function stickyBomb.server_clearBombs(shapeId, detonate)
	if not sm.isHost then return end
	assert(shapeId, "stickyBomb.server_clearBombs: requires argument 'shapeId'")
	local i = 0 for k, v in pairs(stickyBomb.ammo[shapeId] or {}) do i = i + 1 end
	if i == 0 then return end -- no ammo: no reset/clear signal
	table.insert(stickyBomb.server_queued, {shapeId, nil, nil, nil, 0, detonate ~= false}) -- risky, code changes could break this !!!
end

function stickyBomb.server_getBombs(shapeId)
	if not sm.isHost then return end
	assert(shapeId, "stickyBomb.server_getBombs: requires argument 'shapeId'")
	if not stickyBomb.ammo[shapeId] then stickyBomb.ammo[shapeId] = {} end -- it'll still be able to give a reference :)
	return stickyBomb.ammo[shapeId]
end


if reload then reload() end -- makes globalscript reload this properly when this file gets updated.