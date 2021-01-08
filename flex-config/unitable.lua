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
local json = require('dkjson')

-- Single table that can take any OSM object and any geometry.
local dtable = osm2pgsql.define_table{
    name = "unitable",
    schema = schema_name,
    -- This will generate a column "osm_id INT8" for the id, and a column
    -- "geom_type CHAR(1)" for the type of object: N(ode), W(way), R(relation)
    ids = { type = 'any', id_column = 'osm_id', type_column = 'geom_type' },
    columns = {
        { column = 'tags',  type = 'jsonb' },
        { column = 'geom',  type = 'geometry', projection = srid  },
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
    dtable:add_row({
        tags = json.encode(object.tags),
        geom = { create = geometry_type }
    })
end

function osm2pgsql.process_node(object)
    process(object, 'point')
end

function osm2pgsql.process_way(object)
    process(object, 'line')
end

function osm2pgsql.process_relation(object)
    if clean_tags(object.tags) then
        return
    end

    if object.tags.type == 'multipolygon' or object.tags.type == 'boundary' then
        dtable:add_row({
            tags = json.encode(object.tags),
            geom = { create = 'area' }
        })
    end
end

