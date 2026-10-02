---@class ArcaTargetOption
---@field name? string unique per target, used for removal
---@field label string
---@field icon? string font awesome class
---@field distance? number
---@field groups? string|string[]|table<string, number> job/gang names, or name = min grade
---@field canInteract? fun(entity: number, distance: number, coords: vector3, name: string): boolean
---@field onSelect? fun(data: table)
---@field event? string
---@field serverEvent? string
---@field command? string

Targets = {
    global = { ped = {}, vehicle = {}, object = {}, player = {} },
    models = {},       -- [hash] = options
    entities = {},     -- [netId] = options
    localEntities = {},-- [handle] = options
    zones = {},        -- [id] = zone
}

local zoneId = 0
local optionId = 0

local function toList(value)
    if type(value) ~= 'table' or value.label or value.x then return { value } end
    return value
end

---Normalises options and tags them with the calling resource for cleanup
local function prepare(options)
    local resource = GetInvokingResource() or GetCurrentResourceName()
    options = toList(options)
    for i = 1, #options do
        local opt = options[i]
        if not opt.name then
            optionId = optionId + 1
            opt.name = ('%s_%d'):format(resource, optionId)
        end
        opt.resource = resource
    end
    return options
end

local function append(list, options)
    for i = 1, #options do
        local opt = options[i]
        for j = #list, 1, -1 do
            if list[j].name == opt.name then table.remove(list, j) end
        end
        list[#list + 1] = opt
    end
end

local function removeNames(list, names)
    if not list then return end
    if names == nil then
        for i = #list, 1, -1 do list[i] = nil end
        return
    end
    local lookup = {}
    for _, n in ipairs(toList(names)) do lookup[n] = true end
    for i = #list, 1, -1 do
        if lookup[list[i].name] then table.remove(list, i) end
    end
end

---------------------------------------------------------------------
-- Globals
---------------------------------------------------------------------
for _, kind in ipairs({ 'ped', 'vehicle', 'object', 'player' }) do
    local Name = kind:sub(1, 1):upper() .. kind:sub(2)
    exports('addGlobal' .. Name, function(options)
        append(Targets.global[kind], prepare(options))
    end)
    exports('removeGlobal' .. Name, function(names)
        removeNames(Targets.global[kind], names)
    end)
end

---------------------------------------------------------------------
-- Models
---------------------------------------------------------------------
local function modelHash(m) return type(m) == 'string' and joaat(m) or m end

exports('addModel', function(models, options)
    options = prepare(options)
    for _, m in ipairs(toList(models)) do
        local hash = modelHash(m)
        Targets.models[hash] = Targets.models[hash] or {}
        append(Targets.models[hash], options)
    end
end)

exports('removeModel', function(models, names)
    for _, m in ipairs(toList(models)) do
        removeNames(Targets.models[modelHash(m)], names)
    end
end)

---------------------------------------------------------------------
-- Networked entities (by net id) and local entities (by handle)
---------------------------------------------------------------------
exports('addEntity', function(netIds, options)
    options = prepare(options)
    for _, id in ipairs(toList(netIds)) do
        Targets.entities[id] = Targets.entities[id] or {}
        append(Targets.entities[id], options)
    end
end)

exports('removeEntity', function(netIds, names)
    for _, id in ipairs(toList(netIds)) do removeNames(Targets.entities[id], names) end
end)

exports('addLocalEntity', function(entities, options)
    options = prepare(options)
    for _, ent in ipairs(toList(entities)) do
        Targets.localEntities[ent] = Targets.localEntities[ent] or {}
        append(Targets.localEntities[ent], options)
    end
end)

exports('removeLocalEntity', function(entities, names)
    for _, ent in ipairs(toList(entities)) do removeNames(Targets.localEntities[ent], names) end
end)

---------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------
local function addZone(zone)
    zoneId = zoneId + 1
    zone.id = zoneId
    zone.options = prepare(zone.options)
    zone.resource = GetInvokingResource() or GetCurrentResourceName()
    Targets.zones[zoneId] = zone
    return zoneId
end

---@param data { coords: vector3, radius?: number, options: ArcaTargetOption[], name?: string, debug?: boolean }
exports('addSphereZone', function(data)
    data.type = 'sphere'
    data.coords = vec3(data.coords.x, data.coords.y, data.coords.z)
    data.radius = data.radius or 1.5
    return addZone(data)
end)

---@param data { coords: vector3, size?: vector3, rotation?: number, options: ArcaTargetOption[], name?: string, debug?: boolean }
exports('addBoxZone', function(data)
    data.type = 'box'
    data.coords = vec3(data.coords.x, data.coords.y, data.coords.z)
    data.size = data.size or vec3(2, 2, 2)
    data.rotation = data.rotation or 0.0
    return addZone(data)
end)

---@param id number|string zone id or zone name
exports('removeZone', function(id)
    if Targets.zones[id] then
        Targets.zones[id] = nil
        return
    end
    for zid, zone in pairs(Targets.zones) do
        if zone.name == id then Targets.zones[zid] = nil end
    end
end)

---------------------------------------------------------------------
-- Cleanup when a resource that registered targets stops
---------------------------------------------------------------------
local function purge(list, resource)
    for i = #list, 1, -1 do
        if list[i].resource == resource then table.remove(list, i) end
    end
end

AddEventHandler('onClientResourceStop', function(resource)
    for _, list in pairs(Targets.global) do purge(list, resource) end
    for _, list in pairs(Targets.models) do purge(list, resource) end
    for _, list in pairs(Targets.entities) do purge(list, resource) end
    for _, list in pairs(Targets.localEntities) do purge(list, resource) end
    for id, zone in pairs(Targets.zones) do
        if zone.resource == resource then Targets.zones[id] = nil end
    end
end)
