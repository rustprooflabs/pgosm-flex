require "helpers"

local index_spec_file = 'indexes/road_major.ini'
local indexes_line = get_indexes_from_spec(index_spec_file, 'line')


local tables = {}

tables.road_major = osm2pgsql.define_table({
    name = 'road_major',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id', create_index = 'unique' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'ref', type = 'text' },
        { column = 'maxspeed', type = 'int' },
        { column = 'layer', type = 'int', not_null = true },
        { column = 'tunnel', type = 'text' },
        { column = 'bridge', type = 'text' },
        { column = 'major', type = 'boolean', not_null = true},
        { column = 'member_ids', type = 'jsonb'},
        { column = 'geom', type = 'multilinestring', projection = srid, not_null = true },
    },
    indexes = indexes_line
})


function road_major_process_way(object)
    if not object.tags.highway then
        return
    end

    if not major_road(object.tags.highway) then
        return
    end

    local major = true

    local name = get_name(object.tags)
    local osm_type = object.tags.highway
    local ref = get_ref(object.tags)
    
    -- in km/hr
    local maxspeed = parse_speed(object.tags.maxspeed)
    local layer = parse_layer_value(object.tags.layer)
    local tunnel = object:grab_tag('tunnel')
    local bridge = object:grab_tag('bridge')

    tables.road_major:insert({
        name = name,
        osm_type = osm_type,
        ref = ref,
        maxspeed = maxspeed,
        major = major,
        layer = layer,
        tunnel = tunnel,
        bridge = bridge,
        geom = object:as_linestring()
    })

end


function road_major_process_relation(object)
    if not object.tags.highway then
        return
    end

    if not major_road(object.tags.highway) then
        return
    end

    local member_ids = osm2pgsql.way_member_ids(object)

    local major = true

    local name = get_name(object.tags)
    local osm_type = object.tags.highway
    local ref = get_ref(object.tags)

    -- in km/hr
    local maxspeed = parse_speed(object.tags.maxspeed)

    -- results in nil for reversible and alternating
    local oneway = object.tags.oneway or 0

    local layer = parse_layer_value(object.tags.layer)
    local tunnel = object.tags.tunnel
    local bridge = object.tags.bridge
    local access = object.tags.access

    tables.road_major:insert({
        name = name,
        osm_type = osm_type,
        ref = ref,
        maxspeed = maxspeed,
        major = major,
        layer = layer,
        tunnel = tunnel,
        bridge = bridge,
        member_ids = member_ids,
        geom = object:as_multilinestring()
    })

end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = road_major_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        road_major_process_way(object_copy)
    end
end


if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = road_major_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        road_major_process_relation(object_copy)
    end

end
