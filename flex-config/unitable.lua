-- Converted from https://github.com/openstreetmap/osm2pgsql/blob/master/flex-config/unitable.lua
--   to use JSONB instead of HSTORE and osm schema.

-- Put all OSM data into a single table
local json = require('dkjson')

-- Change SRID if desired
local srid = 3857

-- We define a single table that can take any OSM object and any geometry.
-- XXX expire will currently not work on these tables.
local dtable = osm2pgsql.define_table{
    name = "data",
    schema = 'osm',
    -- This will generate a column "osm_id INT8" for the id, and a column
    -- "osm_type CHAR(1)" for the type of object: N(ode), W(way), R(relation)
    ids = { type = 'any', id_column = 'osm_id', type_column = 'osm_type' },
    columns = {
        { column = 'attrs', type = 'jsonb' },
        { column = 'tags',  type = 'jsonb' },
        { column = 'geom',  type = 'geometry', projection = srid  },
    }
}

-- print("columns=" .. inspect(dtable:columns()))

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
        attrs = json.encode({
            version = object.version,
            timestamp = object.timestamp,
        }),
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
            attrs = json.encode({
                version = object.version,
                timestamp = object.timestamp,
            }),
            tags = json.encode(object.tags),
            geom = { create = 'area' }
        })
    end
end

