require "helpers"

local index_spec_file = 'indexes/place.ini'
local indexes_point = get_indexes_from_spec(index_spec_file, 'point')
local indexes_line = get_indexes_from_spec(index_spec_file, 'line')
local indexes_polygon = get_indexes_from_spec(index_spec_file, 'polygon')

-------------------------------------------------
-- End of indexes
-------------------------------------------------


local tables = {}


tables.place_point = osm2pgsql.define_table({
    name = 'place_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'boundary', type = 'text' },
        { column = 'admin_level', type = 'int4' },
        { column = 'name', type = 'text' },
        { column = 'geom', type = 'point', projection = srid, not_null = true},
    },
    indexes = indexes_point
})

tables.place_line = osm2pgsql.define_table({
    name = 'place_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'boundary', type = 'text' },
        { column = 'admin_level', type = 'int4' },
        { column = 'name', type = 'text' },
        { column = 'geom', type = 'linestring', projection = srid, not_null = true},
    },
    indexes = indexes_line
})


tables.place_polygon = osm2pgsql.define_table({
    name = 'place_polygon',
    schema = schema_name,
    ids = { type = 'area', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'boundary', type = 'text' },
        { column = 'admin_level', type = 'int4' },
        { column = 'name', type = 'text' },
        { column = 'member_ids', type = 'jsonb'},
        { column = 'geom', type = 'multipolygon', projection = srid, not_null = true},
    },
    indexes = indexes_polygon
})


function place_process_node(object)
    if not object.tags.place
        and not object.tags.boundary
        and not object.tags.admin_level then
        return
    end

    local osm_type

    if object.tags.place then
        osm_type = object:grab_tag('place')
    elseif object.tags.boundary then
        osm_type = 'boundary'
    elseif object.tags.admin_level then
        osm_type = 'admin_level'
    end
    
    local boundary = object:grab_tag('boundary')
    local admin_level = parse_admin_level(object:grab_tag('admin_level'))
    local name = get_name(object.tags)

    tables.place_point:insert({
        osm_type = osm_type,
        boundary = boundary,
        admin_level = admin_level,
        name = name,
        geom = object:as_point()
    })

end


function place_process_way(object)
    if not object.tags.place
        and not object.tags.boundary
        and not object.tags.admin_level
        then
        return
    end

    if object.tags.place then
        osm_type = object:grab_tag('place')
    elseif object.tags.boundary then
        osm_type = 'boundary'
    elseif object.tags.admin_level then
        osm_type = 'admin_level'
    end
    

    local boundary = object:grab_tag('boundary')
    local admin_level = parse_admin_level(object:grab_tag('admin_level'))
    local name = get_name(object.tags)

    if object.is_closed then
        tables.place_polygon:insert({
            osm_type = osm_type,
            boundary = boundary,
            admin_level = admin_level,
            name = name,
            geom = object:as_polygon()
        })
    else
        tables.place_line:insert({
            osm_type = osm_type,
            boundary = boundary,
            admin_level = admin_level,
            name = name,
            geom = object:as_linestring()
        })
    end
    
end


function place_process_relation(object)
    if not object.tags.place
        and not object.tags.boundary
        and not object.tags.admin_level
        then
        return
    end

    if object.tags.place then
        osm_type = object:grab_tag('place')
    elseif object.tags.boundary then
        osm_type = 'boundary'
    elseif object.tags.admin_level then
        osm_type = 'admin_level'
    end
    

    local boundary = object:grab_tag('boundary')
    local admin_level = parse_admin_level(object:grab_tag('admin_level'))
    local name = get_name(object.tags)
    local member_ids = osm2pgsql.way_member_ids(object)

    tables.place_polygon:insert({
        osm_type = osm_type,
        boundary = boundary,
        admin_level = admin_level,
        name = name,
        member_ids = member_ids,
        geom = object:as_multipolygon()
    })

end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = place_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        place_process_node(object_copy)
    end
end



if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = place_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        place_process_way(object_copy)
    end
end


if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = place_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        place_process_relation(object_copy)
    end
end
