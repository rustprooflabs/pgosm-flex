require "helpers"

local tables = {}

tables.water_point = osm2pgsql.define_table({
    name = 'water_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'layer', type = 'int', not_null = true },
        { column = 'tunnel', type = 'text' },
        { column = 'bridge', type = 'text' },
        { column = 'boat', type = 'text' },
        { column = 'geom', type = 'point', projection = srid, not_null = true},
    }
})


tables.water_line = osm2pgsql.define_table({
    name = 'water_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'layer', type = 'int', not_null = true },
        { column = 'tunnel', type = 'text' },
        { column = 'bridge', type = 'text' },
        { column = 'boat', type = 'text' },
        { column = 'member_ids', type = 'jsonb'},
        { column = 'geom', type = 'multilinestring', projection = srid, not_null = true},
    }
})


tables.water_polygon = osm2pgsql.define_table({
    name = 'water_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'layer', type = 'int', not_null = true },
        { column = 'tunnel', type = 'text' },
        { column = 'bridge', type = 'text' },
        { column = 'boat', type = 'text' },
        { column = 'member_ids', type = 'jsonb'},
        { column = 'geom', type = 'multipolygon', projection = srid, not_null = true},
    }
})


function water_process_node(object)
    if not object.tags.natural
        and not object.tags.waterway then
        return
    end

    if object.tags.natural == 'water'
            or object.tags.natural == 'lake'
            or object.tags.natural == 'hot_spring'
            or object.tags.natural == 'waterfall'
            or object.tags.natural == 'wetland'
            or object.tags.natural == 'swamp'
            or object.tags.natural == 'water_meadow'
            or object.tags.natural == 'waterway'
            or object.tags.natural == 'spring'
            then
        local osm_type = 'natural'
        local osm_subtype = object:grab_tag('natural')
        local name = get_name(object.tags)
        local layer = parse_layer_value(object.tags.layer)
        local tunnel = object:grab_tag('tunnel')
        local bridge = object:grab_tag('bridge')
        local boat = object:grab_tag('boat')

        tables.water_point:insert({
            osm_type = osm_type,
            osm_subtype = osm_subtype,
            name = name,
            layer = layer,
            tunnel = tunnel,
            bridge = bridge,
            boat = boat,
            geom = object:as_point()
        })

    elseif object.tags.waterway then
        local osm_type = 'waterway'
        local osm_subtype = object:grab_tag('waterway')
        local name = get_name(object.tags)
        local layer = parse_layer_value(object.tags.layer)
        local tunnel = object:grab_tag('tunnel')
        local bridge = object:grab_tag('bridge')
        local boat = object:grab_tag('boat')

        tables.water_point:insert({
            osm_type = osm_type,
            osm_subtype = osm_subtype,
            name = name,
            layer = layer,
            tunnel = tunnel,
            bridge = bridge,
            boat = boat,
            geom = object:as_point()
        })

    end


end


function water_process_way(object)
    if not object.tags.natural
        and not object.tags.waterway then
        return
    end

    if object.tags.natural == 'water'
            or object.tags.natural == 'lake'
            or object.tags.natural == 'hot_spring'
            or object.tags.natural == 'waterfall'
            or object.tags.natural == 'wetland'
            or object.tags.natural == 'swamp'
            or object.tags.natural == 'water_meadow'
            or object.tags.natural == 'waterway'
            or object.tags.natural == 'spring'
            then
        local osm_type = 'natural'
        local osm_subtype = object:grab_tag('natural')
        local name = get_name(object.tags)
        local layer = parse_layer_value(object.tags.layer)
        local tunnel = object:grab_tag('tunnel')
        local bridge = object:grab_tag('bridge')
        local boat = object:grab_tag('boat')

        if object.is_closed then
            tables.water_polygon:insert({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                geom = object:as_polygon()
            })
        else
            tables.water_line:insert({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                geom = object:as_linestring()
            })
        end

    elseif object.tags.waterway then
        local osm_type = 'waterway'
        local osm_subtype = object:grab_tag('waterway')
        local name = get_name(object.tags)
        local layer = parse_layer_value(object.tags.layer)
        local tunnel = object:grab_tag('tunnel')
        local bridge = object:grab_tag('bridge')
        local boat = object:grab_tag('boat')

        if object.is_closed then
            tables.water_polygon:insert({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                geom = object:as_polygon()
            })
        else
            tables.water_line:insert({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                geom = object:as_linestring()
            })
        end

    end

end


function water_process_relation(object)
    if not object.tags.natural
        and not object.tags.waterway then
        return
    end

    local member_ids = osm2pgsql.way_member_ids(object)

    if object.tags.natural == 'water'
            or object.tags.natural == 'lake'
            or object.tags.natural == 'hot_spring'
            or object.tags.natural == 'waterfall'
            or object.tags.natural == 'wetland'
            or object.tags.natural == 'swamp'
            or object.tags.natural == 'water_meadow'
            or object.tags.natural == 'waterway'
            or object.tags.natural == 'spring'
            then
        local osm_type = 'natural'
        local osm_subtype = object:grab_tag('natural')
        local name = get_name(object.tags)
        local layer = parse_layer_value(object.tags.layer)
        local tunnel = object:grab_tag('tunnel')
        local bridge = object:grab_tag('bridge')
        local boat = object:grab_tag('boat')

        if object.tags.type == 'multipolygon' then
            tables.water_polygon:insert({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                member_ids = member_ids,
                geom = object:as_multipolygon()
            })
        else
            tables.water_line:insert({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                member_ids = member_ids,
                geom = object:as_multilinestring()
            })
        end

    elseif object.tags.waterway then
        local osm_type = 'waterway'
        local osm_subtype = object:grab_tag('waterway')
        local name = get_name(object.tags)
        local layer = parse_layer_value(object.tags.layer)
        local tunnel = object:grab_tag('tunnel')
        local bridge = object:grab_tag('bridge')
        local boat = object:grab_tag('boat')

        if object.tags.type == 'multipolygon' then
            tables.water_polygon:insert({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                member_ids = member_ids,
                geom = object:as_multipolygon()
            })
        else
            tables.water_line:insert({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                member_ids = member_ids,
                geom = object:as_multilinestring()
            })
        end

    end

    
end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = water_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        water_process_node(object_copy)
    end
end



if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = water_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        water_process_way(object_copy)
    end
end


if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = water_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        water_process_relation(object_copy)
    end
end
