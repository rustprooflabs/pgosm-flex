
-- Use JSON encoder
local json = require('dkjson')

-- Change SRID if desired
local srid = 3857

local tables = {}

tables.natural = osm2pgsql.define_node_table('natural_point', {
    { column = 'osm_type',     type = 'text', not_null = true },
    { column = 'tags',     type = 'jsonb' },
    { column = 'geom',     type = 'point' , projection = srid},
}, { schema = 'osm' })

tables.natural_line = osm2pgsql.define_way_table('natural_line', {
    { column = 'osm_type',     type = 'text', not_null = true },
    { column = 'tags',     type = 'jsonb' },
    { column = 'geom',     type = 'linestring', projection = srid },
}, { schema = 'osm' })


tables.natural_polygon = osm2pgsql.define_way_table('natural_polygon', {
    { column = 'osm_type',     type = 'text' , not_null = true},
    { column = 'tags',     type = 'jsonb' },
    { column = 'geom',     type = 'multipolygon', projection = srid },
}, { schema = 'osm' })



function clean_tags(tags)
    tags.odbl = nil
    tags.created_by = nil
    tags.source = nil
    tags['source:ref'] = nil

    return next(tags) == nil
end


function osm2pgsql.process_node(object)
    -- We are only interested in natural details
    if not object.tags.natural then
        return
    end

    clean_tags(object.tags)

    -- Using grab_tag() removes from remaining key/value saved to Pg
    local osm_type = object:grab_tag('natural')

    tables.natural:add_row({
        tags = json.encode(object.tags),
        osm_type = osm_type,
        geom = { create = 'point' }
    })

end

-- Change function name here
function natural_process_way(object)
    -- We are only interested in highways
    if not object.tags.natural then
        return
    end

    clean_tags(object.tags)

    local osm_type = object:grab_tag('natural')


    if object.is_closed then
        tables.natural_polygon:add_row({
            tags = json.encode(object.tags),
            osm_type = osm_type,
            geom = { create = 'area' }
        })
    else
        tables.natural_line:add_row({
            tags = json.encode(object.tags),
            osm_type = osm_type,
            geom = { create = 'line' }
        })
    end
    
end


-- deep_copy based on copy2: https://gist.github.com/tylerneylon/81333721109155b2d244
function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = setmetatable({}, getmetatable(obj))
    for k, v in pairs(obj) do res[deep_copy(k)] = deep_copy(v) end
    return res
end


if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = natural_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        natural_process_way(object_copy)
    end
end
