local srid = 3857

local tables = {}

tables.indoor_point = osm2pgsql.define_table({
    name = 'indoor_point',
    schema = 'osm',
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'layer',   type = 'int', not_null = false },
        { column = 'level',   type = 'text'},
        { column = 'room',   type = 'text'},
        { column = 'entrance',   type = 'text'},
        { column = 'door',   type = 'text'},
        { column = 'capacity',   type = 'text'},
        { column = 'highway',   type = 'text'},
        { column = 'geom',     type = 'point' , projection = srid},
    }
})


tables.indoor_line = osm2pgsql.define_table({
    name = 'indoor_line',
    schema = 'osm',
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'layer',   type = 'int', not_null = false },
        { column = 'level',   type = 'text'},
        { column = 'room',   type = 'text'},
        { column = 'entrance',   type = 'text'},
        { column = 'door',   type = 'text'},
        { column = 'capacity',   type = 'text'},
        { column = 'highway',   type = 'text'},
        { column = 'geom',     type = 'linestring' , projection = srid},
    }
})


tables.indoor_polygon = osm2pgsql.define_table({
    name = 'indoor_polygon',
    schema = 'osm',
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'layer',   type = 'int', not_null = false },
        { column = 'level',   type = 'text'},
        { column = 'room',   type = 'text'},
        { column = 'entrance',   type = 'text'},
        { column = 'door',   type = 'text'},
        { column = 'capacity',   type = 'text'},
        { column = 'highway',   type = 'text'},
        { column = 'geom',     type = 'multipolygon' , projection = srid},
    }
})

function parse_layer_value(input)
    if not input then
        -- We want default value set for all features in Pg
        return 0
    end

    local layer = tonumber(input)

    if layer then
        return layer
    end

end


function indoor_process_node(object)
    if not object.tags.indoor then
        return
    end

    local osm_type = object:grab_tag('indoor')
    local name = object:grab_tag('name')
    local layer = parse_layer_value(object.tags.layer)
    local level = object:grab_tag('level')
    local room = object:grab_tag('room')
    local entrance = object:grab_tag('entrance')
    local door = object:grab_tag('door')
    local capacity = object:grab_tag('capacity')
    local highway = object:grab_tag('highway')

    tables.indoor_point:add_row({
        osm_type = osm_type,
        name = name,
        layer = layer,
        level = level,
        room = room,
        entrance = entrance,
        door = door,
        capacity = capacity,
        highway = highway,
        geom = { create = 'point' }
    })

end


function indoor_process_way(object)
    if not object.tags.indoor then
        return
    end

    local osm_type = object:grab_tag('indoor')
    local name = object:grab_tag('name')
    local layer = parse_layer_value(object.tags.layer)
    local level = object:grab_tag('level')
    local room = object:grab_tag('room')
    local entrance = object:grab_tag('entrance')
    local door = object:grab_tag('door')
    local capacity = object:grab_tag('capacity')
    local highway = object:grab_tag('highway')

    if object.is_closed then
        tables.indoor_polygon:add_row({
            osm_type = osm_type,
            name = name,
            layer = layer,
            level = level,
            room = room,
            entrance = entrance,
            door = door,
            capacity = capacity,
            highway = highway,
            geom = { create = 'area' }
        })
    else
        tables.indoor_line:add_row({
            osm_type = osm_type,
            name = name,
            layer = layer,
            level = level,
            room = room,
            entrance = entrance,
            door = door,
            capacity = capacity,
            highway = highway,
            geom = { create = 'line' }
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
    osm2pgsql.process_node = indoor_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        indoor_process_node(object_copy)
    end
end



if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = indoor_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        indoor_process_way(object_copy)
    end
end
