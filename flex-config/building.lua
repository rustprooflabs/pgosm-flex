require "helpers"

local tables = {}


tables.building_point = osm2pgsql.define_table({
    name = 'building_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = true},
        { column = 'name',     type = 'text' },
        { column = 'levels',  type = 'int'},
        { column = 'height',  type = 'numeric'},
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'wheelchair', type = 'bool'},
        { column = 'operator', type = 'text'},
        { column = 'geom',     type = 'point', projection = srid},
    }
})


tables.building_polygon = osm2pgsql.define_table({
    name = 'building_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = true},
        { column = 'name',     type = 'text' },
        { column = 'levels',  type = 'int'},
        { column = 'height',  type = 'numeric'},
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'wheelchair', type = 'bool'},
        { column = 'operator', type = 'text'},
        { column = 'geom',     type = 'multipolygon', projection = srid},
    }
})


function parse_building_height(input)
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

-- Change function name here
function building_process_node(object)
    if not object.tags.building then
        return
    end

    local osm_type = object:grab_tag('building')
    local name = object:grab_tag('name')
    local street = object:grab_tag('addr:street')
    local city = object:grab_tag('addr:city')
    local state = object:grab_tag('addr:state')
    local wheelchair = object:grab_tag('wheelchair')
    local levels = object:grab_tag('building:levels')
    local height = parse_building_height(object.tags['height'])
    local housenumber  = object:grab_tag('addr:housenumber')
    local operator  = object:grab_tag('operator')

    tables.building_point:add_row({
        osm_type = osm_type,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        wheelchair = wheelchair,
        levels = levels,
        height = height,
        operator = operator,
        geom = { create = 'point' }
    })


end

-- Change function name here
function building_process_way(object)
    if not object.tags.building then
        return
    end

    if not object.is_closed then
        return
    end

    -- Using grab_tag() removes from remaining key/value saved to Pg
    local osm_type = object:grab_tag('building')
    local name = object:grab_tag('name')
    local street = object:grab_tag('addr:street')
    local city = object:grab_tag('addr:city')
    local state = object:grab_tag('addr:state')
    local wheelchair = object:grab_tag('wheelchair')
    local levels = object:grab_tag('building:levels')
    local height = parse_building_height(object.tags['height'])
    local housenumber  = object:grab_tag('addr:housenumber')
    local operator  = object:grab_tag('operator')

    tables.building_polygon:add_row({
        osm_type = osm_type,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        wheelchair = wheelchair,
        levels = levels,
        height = height,
        operator = operator,
        geom = { create = 'area' }
    })


end

-- deep_copy based on copy2: https://gist.github.com/tylerneylon/81333721109155b2d244
function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = setmetatable({}, getmetatable(obj))
    for k, v in pairs(obj) do res[deep_copy(k)] = deep_copy(v) end
    return res
end


if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = building_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        building_process_way(object_copy)
    end
end


if osm2pgsql.process_node == nil then
    -- Change function name here
    osm2pgsql.process_node = building_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        building_process_node(object_copy)
    end
end
