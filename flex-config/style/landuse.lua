require "helpers"

local tables = {}


tables.landuse_point = osm2pgsql.define_table({
    name = 'landuse_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text' , not_null = true},
        { column = 'name', type = 'text' },
        { column = 'geom', type = 'point', projection = srid, not_null = true},
    }
})


tables.landuse_polygon = osm2pgsql.define_table({
    name = 'landuse_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true},
        { column = 'name', type = 'text' },
        { column = 'geom', type = 'multipolygon', projection = srid, not_null = true},
    }
})


-- Change function name here
function landuse_process_node(object)
    if not object.tags.landuse then
        return
    end

    local osm_type = object:grab_tag('landuse')
    local name = get_name(object.tags)

    tables.landuse_point:insert({
        osm_type = osm_type,
        name = name,
        geom = object:as_point()
    })


end

-- Change function name here
function landuse_process_way(object)
    if not object.tags.landuse then
        return
    end

    if not object.is_closed then
        return
    end

    local osm_type = object:grab_tag('landuse')
    local name = get_name(object.tags)

    tables.landuse_polygon:insert({
        osm_type = osm_type,
        name = name,
        geom = object:as_polygon()
    })

end


function landuse_process_relation(object)
    if not object.tags.landuse then
        return
    end

    local osm_type = object:grab_tag('landuse')
    local name = get_name(object.tags)

    if object.tags.type == 'multipolygon' or object.tags.type == 'boundary' then
        tables.landuse_polygon:insert({
            osm_type = osm_type,
            name = name,
            geom = object:as_multipolygon()
        })
    end
end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = landuse_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        landuse_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = landuse_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        landuse_process_way(object_copy)
    end
end


if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = landuse_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        landuse_process_relation(object_copy)
    end
end
