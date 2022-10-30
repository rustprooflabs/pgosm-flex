require "helpers"

local tables = {}


tables.leisure_point = osm2pgsql.define_table({
    name = 'leisure_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true},
        { column = 'name', type = 'text' },
        { column = 'geom', type = 'point', projection = srid, not_null = true},
    }
})


tables.leisure_polygon = osm2pgsql.define_table({
    name = 'leisure_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text' , not_null = true},
        { column = 'name', type = 'text' },
        { column = 'geom', type = 'multipolygon', projection = srid, not_null = true},
    }
})


function leisure_process_node(object)
    if not object.tags.leisure then
        return
    end

    local osm_type = object:grab_tag('leisure')
    local name = get_name(object.tags)

    tables.leisure_point:insert({
        osm_type = osm_type,
        name = name,
        geom = object:as_point()
    })

end


function leisure_process_way(object)
    if not object.tags.leisure then
        return
    end

    if not object.is_closed then
        return
    end

    local osm_type = object:grab_tag('leisure')
    local name = get_name(object.tags)

    tables.leisure_polygon:insert({
        osm_type = osm_type,
        name = name,
        geom = object:as_polygon()
    })

end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = leisure_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        leisure_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = leisure_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        leisure_process_way(object_copy)
    end
end
