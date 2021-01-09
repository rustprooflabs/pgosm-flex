require "helpers"

local tables = {}


tables.leisure_point = osm2pgsql.define_table({
    name = 'leisure_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = true},
        { column = 'name',     type = 'text' },
        { column = 'geom',     type = 'point', projection = srid},
    }
})


tables.leisure_polygon = osm2pgsql.define_table({
    name = 'leisure_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text' , not_null = true},
        { column = 'name',     type = 'text' },
        { column = 'geom',     type = 'multipolygon', projection = srid},
    }
})


-- Change function name here
function leisure_process_node(object)
    if not object.tags.leisure then
        return
    end

    local osm_type = object:grab_tag('leisure')
    local name = object:grab_tag('name')

    tables.leisure_point:add_row({
        osm_type = osm_type,
        name = name,
        geom = { create = 'point' }
    })


end

-- Change function name here
function leisure_process_way(object)
    if not object.tags.leisure then
        return
    end

    if not object.is_closed then
        return
    end

    -- Using grab_tag() removes from remaining key/value saved to Pg
    local osm_type = object:grab_tag('leisure')
    local name = object:grab_tag('name')

    tables.leisure_polygon:add_row({
        osm_type = osm_type,
        name = name,
        geom = { create = 'area' }
    })


end


if osm2pgsql.process_node == nil then
    -- Change function name here
    osm2pgsql.process_node = leisure_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        leisure_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = leisure_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        leisure_process_way(object_copy)
    end
end
