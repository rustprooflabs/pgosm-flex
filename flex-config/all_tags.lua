require "helpers"

-- Put all OSM tag data into a single table w/out geometry
local json = require('dkjson')


local tags_table = osm2pgsql.define_table{
    name = "tags",
    schema = 'osm',
    -- This will generate a column "osm_id INT8" for the id, and a column
    -- "geom_type CHAR(1)" for the type of object: N(ode), W(way), R(relation)
    ids = { type = 'any', id_column = 'osm_id', type_column = 'geom_type' },
    columns = {
        { column = 'tags',  type = 'jsonb' },
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

function process(object, geometry_type)
    if clean_tags(object.tags) then
        return
    end
    tags_table:add_row({
        tags = json.encode(object.tags)
    })
end

function all_tags_process_node(object)
    process(object, 'point')
end

function all_tags_process_way(object)
    process(object, 'line')
end

function all_tags_process_relation(object)
    if clean_tags(object.tags) then
        return
    end

    if object.tags.type == 'multipolygon' or object.tags.type == 'boundary' then
        tags_table:add_row({
            tags = json.encode(object.tags),
            geom = { create = 'area' }
        })
    end
end



if osm2pgsql.process_node == nil then
    -- Change function name here
    osm2pgsql.process_node = all_tags_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        all_tags_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = all_tags_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        all_tags_process_way(object_copy)
    end
end



if osm2pgsql.process_relation == nil then
    -- Change function name here
    osm2pgsql.process_relation = all_tags_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        all_tags_process_relation(object_copy)
    end
end
