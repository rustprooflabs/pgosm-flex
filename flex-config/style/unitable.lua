-- Converted from https://github.com/openstreetmap/osm2pgsql/blob/master/flex-config/unitable.lua
--   to use JSONB instead of HSTORE and osm schema.
--
-------------------------
--  WARNING:   This layer is NOT intended for production use!
--  Use this to explore data when building proper structures!
-------------------------
--
-- Includes tags in JSONB (does not rely on all_tags.lua)
-- Does NOT include deep copy for easy use with "require" like other scripts in this project.
--
require "helpers"


-- Single table that can take any OSM object and any geometry.
local dtable = osm2pgsql.define_table{
    name = "unitable",
    schema = schema_name,
    -- This will generate a column "osm_id INT8" for the id, and a column
    -- "geom_type CHAR(1)" for the type of object: N(ode), W(way), R(relation)
    ids = { type = 'any', id_column = 'osm_id', type_column = 'geom_type' },
    columns = {
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'geometry', projection = srid, not_null = true },
    }
}

-- Helper function to remove some of the tags we usually are not interested in.
-- Returns true if there are no tags left.
function clean_tags(tags)
    tags.odbl = nil
    tags.created_by = nil
    tags.source = nil
    tags['source:ref'] = nil

    return next(tags) == nil
end



function unitable_process_node(object)
    if clean_tags(object.tags) then
        return
    end
    dtable:insert({
        tags = object.tags,
        geom = object:as_point()
    })
end


function unitable_process_way(object)
    if clean_tags(object.tags) then
        return
    end
    dtable:insert({
        tags = object.tags,
        geom = object:as_linestring()
    })
end

-- Main relation types from https://wiki.openstreetmap.org/wiki/Types_of_relation
function unitable_process_relation(object)
    if clean_tags(object.tags) then
        return
    end

    if (object.tags.type == 'multipolygon'
            or object.tags.type == 'boundary')
            then
        dtable:insert({
            tags = object.tags,
            geom = object:as_multipolygon()
        })
    elseif (object.tags.type == 'route'
            or object.tags.type == 'route_master'
            or object.tags.type == 'public_transport'
            or object.tags.type == 'waterway'
            or object.tags.type == 'network'
            or object.tags.type == 'building'
            or object.tags.type == 'street'
            or object.tags.type == 'bridge'
            or object.tags.type == 'tunnel'
            )
            then
        dtable:insert({
            tags = object.tags,
            geom = object:as_multilinestring()
        })
    end

end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = unitable_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        unitable_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = unitable_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        unitable_process_way(object_copy)
    end
end


if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = unitable_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        unitable_process_relation(object_copy)
    end
end
