local active, menuOpen, disabled = false, false, false
local current = { options = {}, entity = 0, coords = nil, distance = 0, signature = '' }

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function rotationToDirection(rot)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(x))
    return vec3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function raycast()
    local origin = GetGameplayCamCoord()
    local dest = origin + rotationToDirection(GetGameplayCamRot(2)) * TargetConfig.MaxDistance
    local handle = StartShapeTestLosProbe(origin.x, origin.y, origin.z, dest.x, dest.y, dest.z, 511, PlayerPedId(), 4)
    local status, hit, coords, _, entity
    repeat
        status, hit, coords, _, entity = GetShapeTestResult(handle)
        if status == 1 then Wait(0) end
    until status ~= 1
    return hit == 1, coords, entity
end

local function inZone(zone, point)
    if zone.type == 'sphere' then
        return #(point - zone.coords) <= zone.radius
    end
    -- box: rotate the point into the box's local space
    local rel = point - zone.coords
    local h = math.rad(-zone.rotation)
    local c, s = math.cos(h), math.sin(h)
    local lx, ly = rel.x * c - rel.y * s, rel.x * s + rel.y * c
    local half = zone.size / 2
    return math.abs(lx) <= half.x and math.abs(ly) <= half.y and math.abs(rel.z) <= half.z
end

local playerData = exports.arca_core:GetPlayerData()
AddEventHandler('arca_core:client:onPlayerLoaded', function(data) playerData = data end)
AddEventHandler('arca_core:client:onPlayerDataUpdated', function(data) playerData = data end)
AddEventHandler('arca_core:client:onPlayerUnloaded', function() playerData = {} end)

local function hasGroup(groups)
    if not groups then return true end
    local pd = playerData
    if not pd or not pd.job then return false end
    local job, gang = pd.job, pd.gang or {}

    local function check(name, minGrade)
        if job.name == name and job.grade.level >= (minGrade or 0) then return true end
        if gang.name == name and gang.grade.level >= (minGrade or 0) then return true end
        return false
    end

    if type(groups) == 'string' then return check(groups) end
    if groups[1] then
        for _, name in ipairs(groups) do
            if check(name) then return true end
        end
        return false
    end
    for name, grade in pairs(groups) do
        if check(name, grade) then return true end
    end
    return false
end

local function collect(list, out, entity, distance, coords, extra)
    if not list then return end
    for i = 1, #list do
        local opt = list[i]
        if distance <= (opt.distance or TargetConfig.DefaultDistance) and hasGroup(opt.groups) then
            local ok = true
            if opt.canInteract then
                local success, res = pcall(opt.canInteract, entity, distance, coords, opt.name)
                ok = success and res
            end
            if ok then out[#out + 1] = { opt = opt, zone = extra } end
        end
    end
end

local function gatherOptions()
    local hit, coords, entity = raycast()
    local out = {}
    if not hit then return out, 0, nil, 0 end

    local distance = #(GetEntityCoords(PlayerPedId()) - coords)

    if entity ~= 0 and DoesEntityExist(entity) then
        local eType = GetEntityType(entity)
        if eType == 1 then
            collect(IsPedAPlayer(entity) and Targets.global.player or Targets.global.ped, out, entity, distance, coords)
        elseif eType == 2 then
            collect(Targets.global.vehicle, out, entity, distance, coords)
        elseif eType == 3 then
            collect(Targets.global.object, out, entity, distance, coords)
        end
        if eType ~= 0 then
            collect(Targets.models[GetEntityModel(entity)], out, entity, distance, coords)
            if NetworkGetEntityIsNetworked(entity) then
                collect(Targets.entities[NetworkGetNetworkIdFromEntity(entity)], out, entity, distance, coords)
            end
            collect(Targets.localEntities[entity], out, entity, distance, coords)
        end
    else
        entity = 0
    end

    for _, zone in pairs(Targets.zones) do
        if inZone(zone, coords) then
            collect(zone.options, out, entity, distance, coords, zone)
        end
    end

    return out, entity, coords, distance
end

local function sendOptions(list)
    local sig = {}
    local ui = {}
    for i, item in ipairs(list) do
        sig[i] = item.opt.name
        ui[i] = { label = item.opt.label, icon = item.opt.icon }
    end
    local signature = table.concat(sig, '|')
    if signature == current.signature then return end
    current.signature = signature
    SendNUIMessage({ action = 'options', data = ui })
end

---------------------------------------------------------------------
-- Targeting loop
---------------------------------------------------------------------
local function stopTargeting()
    active, menuOpen = false, false
    current = { options = {}, entity = 0, signature = '' }
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })
end

local function startTargeting()
    if active or disabled then return end
    if not exports.arca_core:IsLoggedIn() or IsNuiFocused() or IsPauseMenuActive() then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return end
    active = true
    SendNUIMessage({ action = 'show' })

    CreateThread(function()
        local nextScan = 0
        while active do
            if not menuOpen then
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)

                local now = GetGameTimer()
                if now >= nextScan then
                    nextScan = now + 50
                    local list, entity, coords, distance = gatherOptions()
                    current.options, current.entity, current.coords, current.distance = list, entity, coords, distance
                    sendOptions(list)
                end

                if #current.options > 0 and IsDisabledControlJustPressed(0, 24) then
                    menuOpen = true
                    SetNuiFocus(true, true)
                    SetCursorLocation(0.5, 0.5)
                end
            end
            Wait(0)
        end
    end)
end

RegisterCommand('+arca_target', startTargeting, false)
RegisterCommand('-arca_target', function()
    if active and not menuOpen then stopTargeting() end
end, false)
RegisterKeyMapping('+arca_target', 'Target (third eye)', 'keyboard', TargetConfig.Key)

---------------------------------------------------------------------
-- NUI
---------------------------------------------------------------------
RegisterNUICallback('select', function(data, cb)
    cb(1)
    local item = current.options[tonumber(data.index)]
    local entity, coords, distance = current.entity, current.coords, current.distance
    stopTargeting()
    if not item then return end

    local opt = item.opt
    local payload = {
        entity = entity,
        coords = coords,
        distance = distance,
        name = opt.name,
        zone = item.zone and (item.zone.name or item.zone.id) or nil,
    }

    if opt.onSelect then opt.onSelect(payload) end
    if opt.event then TriggerEvent(opt.event, payload) end
    if opt.serverEvent then
        payload.entity = entity ~= 0 and NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or 0
        TriggerServerEvent(opt.serverEvent, payload)
    end
    if opt.command then ExecuteCommand(opt.command) end
end)

RegisterNUICallback('close', function(_, cb)
    cb(1)
    stopTargeting()
end)

---------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------
exports('disableTargeting', function(state)
    disabled = state
    if state and active then stopTargeting() end
end)

exports('isActive', function() return active end)

AddEventHandler('arca_core:client:onPlayerUnloaded', function()
    if active then stopTargeting() end
end)

CreateThread(function()
    while true do
        local drew = false
        for _, zone in pairs(Targets.zones) do
            if TargetConfig.Debug or zone.debug then
                drew = true
                local c = zone.coords
                if zone.type == 'sphere' then
                    local d = zone.radius * 2
                    DrawMarker(28, c.x, c.y, c.z, 0, 0, 0, 0, 0, 0, d, d, d, 76, 141, 255, 80, false, false, 2, false, nil, nil, false)
                else
                    local s = zone.size
                    DrawMarker(43, c.x, c.y, c.z - s.z / 2, 0, 0, 0, 0, 0, zone.rotation, s.x, s.y, s.z, 76, 141, 255, 80, false, false, 2, false, nil, nil, false)
                end
            end
        end
        Wait(drew and 0 or 1000)
    end
end)
