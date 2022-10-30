require "helpers"

local tables = {}


tables.natural_point = osm2pgsql.define_table({
    name = 'natural_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'geom', type = 'point', projection = srid, not_null = true},
    }
})


tables.natural_line = osm2pgsql.define_table({
    name = 'natural_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'geom', type = 'linestring' , projection = srid, not_null = true},
    }
})


tables.natural_polygon = osm2pgsql.define_table({
    name = 'natural_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'ele', type = 'int' },
        { column = 'geom', type = 'multipolygon' , projection = srid, not_null = true},
    }
})


function natural_process_node(object)
    -- We are only interested in natural details
    if not object.tags.natural then
        return
    end

    -- Not interetested in tags caught in water.lua
    if object.tags.natural == 'water'
            or object.tags.natural == 'lake'
            or object.tags.natural == 'hot_spring'
            or object.tags.natural == 'waterfall'
            or object.tags.natural == 'wetland'
            or object.tags.natural == 'swamp'
            or object.tags.natural == 'water_meadow'
            or object.tags.natural == 'waterway'
            or object.tags.natural == 'spring'
            then
        return
    end

    -- Using grab_tag() removes from remaining key/value saved to Pg
    local osm_type = object:grab_tag('natural')
    local name = get_name(object.tags)
    local ele = parse_to_meters(object.tags.ele)

    tables.natural_point:insert({
        osm_type = osm_type,
        name = name,
        ele = ele,
        geom = object:as_point()
    })

end


function natural_process_way(object)
    if not object.tags.natural then
        return
    end

    -- Not interetested in tags caught in water.lua
    if object.tags.natural == 'water'
            or object.tags.natural == 'lake'
            or object.tags.natural == 'hot_spring'
            or object.tags.natural == 'waterfall'
            or object.tags.natural == 'wetland'
            or object.tags.natural == 'swamp'
            or object.tags.natural == 'water_meadow'
            or object.tags.natural == 'waterway'
            or object.tags.natural == 'spring'
            then
        return
    end

    local osm_type = object:grab_tag('natural')
    local name = get_name(object.tags)
    local ele = parse_to_meters(object.tags.ele)

    if object.is_closed then
        tables.natural_polygon:insert({
            osm_type = osm_type,
            name = name,
            ele = ele,
            geom = object:as_polygon()
        })
    else
        tables.natural_line:insert({
            osm_type = osm_type,
            name = name,
            ele = ele,
            geom = object:as_linestring()
        })
    end
    
end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = natural_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        natural_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = natural_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        natural_process_way(object_copy)
    end
end
