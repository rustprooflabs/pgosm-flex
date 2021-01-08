require "helpers"

local tables = {}

tables.road_major = osm2pgsql.define_table({
    name = 'road_major',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'ref',     type = 'text' },
        { column = 'maxspeed', type = 'int' },
        { column = 'geom',     type = 'linestring', projection = srid },
    }
})


-- Change function name here
function road_major_process_way(object)
    -- We are only interested in highways
    if not object.tags.highway then
        return
    end

    -- Only major highways
    if not (object.tags.highway == 'motorway'
            or object.tags.highway == 'motorway_link'
            or object.tags.highway == 'primary'
            or object.tags.highway == 'primary_link'
            or object.tags.highway == 'secondary'
            or object.tags.highway == 'secondary_link'
            or object.tags.highway == 'tertiary'
            or object.tags.highway == 'tertiary_link'
            or object.tags.highway == 'trunk'
            or object.tags.highway == 'trunk_link')
            then
        return
    end

    -- Using grab_tag() removes from remaining key/value saved to Pg
    local name = object:grab_tag('name')
    local osm_type = object:grab_tag('highway')
    local ref = object:grab_tag('ref')
    -- in km/hr
    maxspeed = parse_speed(object.tags.maxspeed)

    tables.road_major:add_row({
        name = name,
        osm_type = osm_type,
        ref = ref,
        maxspeed = maxspeed,
        geom = { create = 'line' }
    })

end


if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = road_major_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        road_major_process_way(object_copy)
    end
end
