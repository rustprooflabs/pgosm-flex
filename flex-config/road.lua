require "helpers"

-- Change SRID if desired
local srid = 3857

local tables = {}

tables.road_line = osm2pgsql.define_table({
    name = 'road_line',
    schema = 'osm',
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'ref',     type = 'text' },
        { column = 'maxspeed', type = 'int' },
        { column = 'oneway',     type = 'direction' },
        { column = 'geom',     type = 'linestring', projection = srid }
    }
})


function road_process_way(object)
    -- We are only interested in highways
    if not object.tags.highway then
        return
    end

    -- Using grab_tag() removes from remaining key/value saved to Pg
    local name = object:grab_tag('name')
    local osm_type = object:grab_tag('highway')
    local ref = object:grab_tag('ref')
    -- in km/hr
    maxspeed = parse_speed(object.tags.maxspeed)

    oneway = object:grab_tag('oneway') or 0

    tables.road_line:add_row({
        name = name,
        osm_type = osm_type,
        ref = ref,
        maxspeed = maxspeed,
        oneway = oneway,
        geom = { create = 'line' }
    })

end


if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = road_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        road_process_way(object_copy)
    end
end
