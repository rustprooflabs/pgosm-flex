require "helpers"

local index_spec_file = 'indexes/road.ini'
local indexes_point = get_indexes_from_spec(index_spec_file, 'point')
local indexes_line = get_indexes_from_spec(index_spec_file, 'line')
local indexes_polygon = get_indexes_from_spec(index_spec_file, 'polygon')

local tables = {}

tables.road_point = osm2pgsql.define_table({
    name = 'road_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id', create_index = 'unique' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'ref', type = 'text' },
        { column = 'maxspeed', type = 'int' },
        { column = 'oneway', type = 'direction' },
        { column = 'layer', type = 'int', not_null = true },
        { column = 'tunnel', type = 'text' },
        { column = 'bridge', type = 'text' },
        { column = 'access', type = 'text' },
        { column = 'geom', type = 'point', projection = srid, not_null = true }
    },
    indexes = indexes_point
})



tables.road_line = osm2pgsql.define_table({
    name = 'road_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id', create_index = 'unique' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'ref', type = 'text' },
        { column = 'maxspeed', type = 'int' },
        { column = 'oneway', type = 'direction' },
        { column = 'layer', type = 'int', not_null = true },
        { column = 'tunnel', type = 'text' },
        { column = 'bridge', type = 'text' },
        { column = 'major', type = 'boolean', not_null = true},
        { column = 'route_foot', type = 'boolean' },
        { column = 'route_cycle', type = 'boolean' },
        { column = 'route_motor', type = 'boolean' },
        { column = 'access', type = 'text' },
        { column = 'member_ids', type = 'jsonb'},
        { column = 'geom', type = 'multilinestring', projection = srid, not_null = true }
    },
    indexes = indexes_line
})


tables.road_polygon = osm2pgsql.define_table({
    name = 'road_polygon',
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
        { column = 'route_foot', type = 'boolean' },
        { column = 'route_cycle', type = 'boolean' },
        { column = 'route_motor', type = 'boolean' },
        { column = 'access', type = 'text' },
        { column = 'member_ids', type = 'jsonb'},
        { column = 'geom', type = 'multipolygon', projection = srid, not_null = true }
    },
    indexes = indexes_polygon
})



function road_process_node(object)
    if not object.tags.highway then
        return
    end

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

    tables.road_point:insert({
        name = name,
        osm_type = osm_type,
        ref = ref,
        maxspeed = maxspeed,
        oneway = oneway,
        layer = layer,
        tunnel = tunnel,
        bridge = bridge,
        access = access,
        geom = object:as_point()
    })

end

function road_process_way(object)
    if not object.tags.highway then
        return
    end

    local name = get_name(object.tags)
    local route_foot = routable_foot(object.tags)
    local route_cycle = routable_cycle(object.tags)
    local route_motor = routable_motor(object.tags)

    local osm_type = object.tags.highway
    local ref = get_ref(object.tags)

    -- in km/hr
    local maxspeed = parse_speed(object.tags.maxspeed)

    -- results in nil for reversible and alternating
    local oneway = object.tags.oneway or 0

    local major = major_road(osm_type)
    local layer = parse_layer_value(object.tags.layer)
    local tunnel = object.tags.tunnel
    local bridge = object.tags.bridge
    local access = object.tags.access

    if object.tags.area == 'yes'
        or object.tags.indoor == 'room'
            then
        tables.road_polygon:insert({
            name = name,
            osm_type = osm_type,
            ref = ref,
            maxspeed = maxspeed,
            major = major,
            layer = layer,
            tunnel = tunnel,
            bridge = bridge,
            route_foot = route_foot,
            route_cycle = route_cycle,
            route_motor = route_motor,
            access = access,
            geom = object:as_polygon()
        })
    else
        tables.road_line:insert({
            name = name,
            osm_type = osm_type,
            ref = ref,
            maxspeed = maxspeed,
            oneway = oneway,
            major = major,
            layer = layer,
            tunnel = tunnel,
            bridge = bridge,
            route_foot = route_foot,
            route_cycle = route_cycle,
            route_motor = route_motor,
            access = access,
            geom = object:as_linestring()
        })
    end

end


function road_process_relation(object)
    if not object.tags.highway then
        return
    end

    local member_ids = osm2pgsql.way_member_ids(object)

    local name = get_name(object.tags)
    local route_foot = routable_foot(object.tags)
    local route_cycle = routable_cycle(object.tags)
    local route_motor = routable_motor(object.tags)

    local osm_type = object.tags.highway
    local ref = get_ref(object.tags)

    -- in km/hr
    local maxspeed = parse_speed(object.tags.maxspeed)

    -- results in nil for reversible and alternating
    local oneway = object.tags.oneway or 0

    local major = major_road(osm_type)
    local layer = parse_layer_value(object.tags.layer)
    local tunnel = object.tags.tunnel
    local bridge = object.tags.bridge
    local access = object.tags.access

    if object.tags.area == 'yes'
        or object.tags.indoor == 'room'
            then
        tables.road_polygon:insert({
            name = name,
            osm_type = osm_type,
            ref = ref,
            maxspeed = maxspeed,
            major = major,
            layer = layer,
            tunnel = tunnel,
            bridge = bridge,
            route_foot = route_foot,
            route_cycle = route_cycle,
            route_motor = route_motor,
            access = access,
            member_ids = member_ids,
            geom = object:as_multipolygon()
        })
    else
        tables.road_line:insert({
            name = name,
            osm_type = osm_type,
            ref = ref,
            maxspeed = maxspeed,
            oneway = oneway,
            major = major,
            layer = layer,
            tunnel = tunnel,
            bridge = bridge,
            route_foot = route_foot,
            route_cycle = route_cycle,
            route_motor = route_motor,
            access = access,
            member_ids = member_ids,
            geom = object:as_multilinestring()
        })
    end

end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = road_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        road_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = road_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        road_process_way(object_copy)
    end
end


if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = road_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        road_process_relation(object_copy)
    end

end
