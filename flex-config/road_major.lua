-- Use JSON encoder
local json = require('dkjson')

-- Change SRID if desired
local srid = 3857

local tables = {}

tables.road_major = osm2pgsql.define_table({
    name = 'road_major',
    schema = 'osm',
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'ref',     type = 'text' },
        { column = 'maxspeed', type = 'int' },
        { column = 'tags',     type = 'jsonb' },
        { column = 'geom',     type = 'linestring', projection = srid },
    }
})


function clean_tags(tags)
    tags.odbl = nil
    tags.created_by = nil
    tags.source = nil
    tags['source:ref'] = nil

    return next(tags) == nil
end


-- Parse a maxspeed value like "30" or "55 mph" and return a number in km/h
function parse_speed(input)
    -- from osm2pgsql/flex-config/data-types.lua
    if not input then
        return nil
    end

    local maxspeed = tonumber(input)

    -- If maxspeed is just a number, it is in km/h, so just return it
    if maxspeed then
        return maxspeed
    end

    -- If there is an 'mph' at the end, convert to km/h and return
    if input:sub(-3) == 'mph' then
        local num = tonumber(input:sub(1, -4))
        if num then
            return math.floor(num * 1.60934)
        end
    end

    return nil
end


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

    clean_tags(object.tags)

    -- Using grab_tag() removes from remaining key/value saved to Pg
    local name = object:grab_tag('name')
    local osm_type = object:grab_tag('highway')
    local ref = object:grab_tag('ref')
    -- in km/hr
    maxspeed = parse_speed(object.tags.maxspeed)

    tables.road_major:add_row({
        tags = json.encode(object.tags),
        name = name,
        osm_type = osm_type,
        ref = ref,
        maxspeed = maxspeed,
        geom = { create = 'line' }
    })

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
