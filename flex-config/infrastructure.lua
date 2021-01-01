-- Change SRID if desired
local srid = 3857

local tables = {}


-- Rows with any of the following keys will be treated as possible infrastructure
local infrastructure_keys = {
    'aeroway',
    'amenity',
    'emergency',
    'highway',
    'man_made',
    'power',
    'water',
    'waterway'
}

-- Function make_check_in_list_func from: https://github.com/openstreetmap/osm2pgsql/blob/master/flex-config/compatible.lua
function make_check_in_list_func(list)
    local h = {}
    for _, k in ipairs(list) do
        h[k] = true
    end
    return function(tags)
        for k, _ in pairs(tags) do
            if h[k] then
                return true
            end
        end
        return false
    end
end

local is_infrastructure = make_check_in_list_func(infrastructure_keys)


tables.infrastructure_point = osm2pgsql.define_table({
    name = 'infrastructure_point',
    schema = 'osm',
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',   type = 'text'},
        { column = 'name',     type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'height',  type = 'numeric'},
        { column = 'operator', type = 'text'},
        { column = 'geom',     type = 'point' , projection = srid},
    }
})


tables.infrastructure_line = osm2pgsql.define_table({
    name = 'infrastructure_line',
    schema = 'osm',
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'height',  type = 'numeric'},
        { column = 'operator', type = 'text'},
        { column = 'geom',     type = 'linestring' , projection = srid},
    }
})


tables.infrastructure_polygon = osm2pgsql.define_table({
    name = 'infrastructure_polygon',
    schema = 'osm',
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'height',  type = 'numeric'},
        { column = 'operator', type = 'text'},
        { column = 'geom',     type = 'multipolygon' , projection = srid},
    }
})



function parse_height(input)
    if not input then
        return nil
    end

    local height = tonumber(input)

    -- If height is just a number, it is in meters, just return it
    if height then
        return height
    end

    -- If there is an 'ft' at the end, convert to meters and return
    if input:sub(-2) == 'ft' then
        local num = tonumber(input:sub(1, -3))
        if num then
            return num * 0.3048
        end
    end

    return nil
end


-- Parse an ele value like "1800", "1955 m" or "8001 ft" and return a number in meters
function parse_ele(input)
    if not input then
        return nil
    end

    local ele = tonumber(input)

    -- If ele is just a number, it is in meters, so just return it
    if ele then
        return ele
    end

    -- If there is an 'm ' at the end, strip off and return
    if input:sub(-1) == 'm' then
        local num = tonumber(input:sub(1, -2))
        if num then
            return num
        end
    end

    -- If there is an 'ft' at the end, strip off and return
    if input:sub(-2) == 'ft' then
        local num = tonumber(input:sub(1, -3))
        if num then
            return math.floor(num * 0.3048)
        end
    end

    return nil
end


function infrastructure_process_node(object)
    -- We are only interested in some tags
    if not is_infrastructure(object.tags) then
        return
    end

    local name = object:grab_tag('name')
    local ele = parse_ele(object.tags.ele)
    local height = parse_height(object.tags['height'])
    local operator = object.tags.operator

    if object.tags.amenity == 'fire_hydrant'
            or object.tags.emergency == 'fire_hydrant' then
        local osm_type = 'fire_hydrant'

        tables.infrastructure_point:add_row({
            osm_type = osm_type,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            geom = { create = 'point' }
        })

    elseif object.tags.amenity == 'emergency_phone'
            or object.tags.emergency == 'phone' then
        local osm_type = 'emergency_phone'
        
        tables.infrastructure_point:add_row({
            osm_type = osm_type,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            geom = { create = 'point' }
        })

    elseif object.tags.highway == 'emergency_access_point'
            then
        local osm_type = 'emergency_access'
        
        tables.infrastructure_point:add_row({
            osm_type = osm_type,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            geom = { create = 'point' }
        })

    elseif object.tags.man_made == 'tower'
            or object.tags.man_made == 'communications_tower'
            or object.tags.man_made == 'mast'
            or object.tags.man_made == 'silo'
            then
        local osm_type = object.tags.man_made
        local osm_subtype = object.tags['tower:type']
        
        tables.infrastructure_point:add_row({
            osm_type = osm_type,
            osm_subtype = osm_subtype,
            name = name,
            ele = ele,
            height = height,
            operator = operator,
            geom = { create = 'point' }
        })

    end

end



-- deep_copy based on copy2: https://gist.github.com/tylerneylon/81333721109155b2d244
function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = setmetatable({}, getmetatable(obj))
    for k, v in pairs(obj) do res[deep_copy(k)] = deep_copy(v) end
    return res
end


if osm2pgsql.process_node == nil then
    -- Change function name here
    osm2pgsql.process_node = infrastructure_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        infrastructure_process_node(object_copy)
    end
end


--[[]
if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = infrastructure_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        infrastructure_process_way(object_copy)
    end
end ]]--

