require "helpers"

local tables = {}

tables.indoor_point = osm2pgsql.define_table({
    name = 'indoor_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'layer', type = 'int', not_null = false },
        { column = 'level', type = 'text'},
        { column = 'room', type = 'text'},
        { column = 'entrance', type = 'text'},
        { column = 'door', type = 'text'},
        { column = 'capacity', type = 'text'},
        { column = 'highway', type = 'text'},
        { column = 'geom', type = 'point' , projection = srid, not_null = true},
    },
    indexes = {
        { column = 'geom', method = gist_type },
        { column = 'osm_type', method = 'btree' },
    }
})


tables.indoor_line = osm2pgsql.define_table({
    name = 'indoor_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'layer', type = 'int', not_null = false },
        { column = 'level', type = 'text'},
        { column = 'room', type = 'text'},
        { column = 'entrance', type = 'text'},
        { column = 'door', type = 'text'},
        { column = 'capacity', type = 'text'},
        { column = 'highway', type = 'text'},
        { column = 'geom', type = 'linestring', projection = srid, not_null = true},
    },
    indexes = {
        { column = 'geom', method = gist_type },
        { column = 'osm_type', method = 'btree' },
    }
})


tables.indoor_polygon = osm2pgsql.define_table({
    name = 'indoor_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'layer', type = 'int', not_null = false },
        { column = 'level', type = 'text'},
        { column = 'room', type = 'text'},
        { column = 'entrance', type = 'text'},
        { column = 'door', type = 'text'},
        { column = 'capacity', type = 'text'},
        { column = 'highway', type = 'text'},
        { column = 'geom', type = 'multipolygon' , projection = srid, not_null = true},
    },
    indexes = {
        { column = 'geom', method = gist_type },
        { column = 'osm_type', method = 'btree' },
    }
})


local function get_osm_type(object)
    if object.tags.indoor then
        osm_type = object.tags.indoor
    elseif object.tags.door then
        osm_type = 'door'
    elseif object.tags.entrance then
        osm_type = 'entrance'
    else
        osm_type = 'unknown'
    end

    return osm_type
end


local indoor_first_level_keys = {
    'indoor',
    'door',
    'entrance'
}

local is_first_level_indoor = make_check_in_list_func(indoor_first_level_keys)


function indoor_process_node(object)
    if not is_first_level_indoor(object.tags) then
        return
    end

    local osm_type = get_osm_type(object)
    local name = get_name(object.tags)
    local layer = parse_layer_value(object.tags.layer)
    local level = object.tags.level
    local room = object.tags.room
    local entrance = object.tags.entrance
    local door = object.tags.door
    local capacity = object.tags.capacity
    local highway = object.tags.highway

    tables.indoor_point:insert({
        osm_type = osm_type,
        name = name,
        layer = layer,
        level = level,
        room = room,
        entrance = entrance,
        door = door,
        capacity = capacity,
        highway = highway,
        geom = object:as_point()
    })

end


function indoor_process_way(object)
    if not is_first_level_indoor(object.tags) then
        return
    end

    local osm_type = get_osm_type(object)
    local name = get_name(object.tags)
    local layer = parse_layer_value(object.tags.layer)
    local level = object.tags.level
    local room = object.tags.room
    local entrance = object.tags.entrance
    local door = object.tags.door
    local capacity = object.tags.capacity
    local highway = object.tags.highway

    if object.is_closed then
        tables.indoor_polygon:insert({
            osm_type = osm_type,
            name = name,
            layer = layer,
            level = level,
            room = room,
            entrance = entrance,
            door = door,
            capacity = capacity,
            highway = highway,
            geom = object:as_polygon()
        })
    else
        tables.indoor_line:insert({
            osm_type = osm_type,
            name = name,
            layer = layer,
            level = level,
            room = room,
            entrance = entrance,
            door = door,
            capacity = capacity,
            highway = highway,
            geom = object:as_linestring()
        })
    end

end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = indoor_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        indoor_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = indoor_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        indoor_process_way(object_copy)
    end
end
