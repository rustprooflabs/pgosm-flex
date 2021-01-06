require "helpers"

local srid = 3857

local tables = {}

tables.water_point = osm2pgsql.define_table({
    name = 'water_point',
    schema = 'osm',
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'layer',   type = 'int', not_null = true },
        { column = 'tunnel',     type = 'text' },
        { column = 'bridge',     type = 'text' },
        { column = 'boat',     type = 'text' },
        { column = 'geom',     type = 'point' , projection = srid},
    }
})


tables.water_line = osm2pgsql.define_table({
    name = 'water_line',
    schema = 'osm',
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'layer',   type = 'int', not_null = true },
        { column = 'tunnel',     type = 'text' },
        { column = 'bridge',     type = 'text' },
        { column = 'boat',     type = 'text' },
        { column = 'geom',     type = 'linestring' , projection = srid},
    }
})


tables.water_polygon = osm2pgsql.define_table({
    name = 'water_polygon',
    schema = 'osm',
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'layer',   type = 'int', not_null = true },
        { column = 'tunnel',     type = 'text' },
        { column = 'bridge',     type = 'text' },
        { column = 'boat',     type = 'text' },
        { column = 'geom',     type = 'multipolygon' , projection = srid},
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
        local name = object:grab_tag('name')
        local layer = parse_layer_value(object.tags.layer)
        local tunnel = object:grab_tag('tunnel')
        local bridge = object:grab_tag('bridge')
        local boat = object:grab_tag('boat')

        tables.water_point:add_row({
            osm_type = osm_type,
            osm_subtype = osm_subtype,
            name = name,
            layer = layer,
            tunnel = tunnel,
            bridge = bridge,
            boat = boat,
            geom = { create = 'point' }
        })

    elseif object.tags.waterway then
        local osm_type = 'waterway'
        local osm_subtype = object:grab_tag('waterway')
        local name = object:grab_tag('name')
        local layer = parse_layer_value(object.tags.layer)
        local tunnel = object:grab_tag('tunnel')
        local bridge = object:grab_tag('bridge')
        local boat = object:grab_tag('boat')

        tables.water_point:add_row({
            osm_type = osm_type,
            osm_subtype = osm_subtype,
            name = name,
            layer = layer,
            tunnel = tunnel,
            bridge = bridge,
            boat = boat,
            geom = { create = 'point' }
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
        local name = object:grab_tag('name')
        local layer = parse_layer_value(object.tags.layer)
        local tunnel = object:grab_tag('tunnel')
        local bridge = object:grab_tag('bridge')
        local boat = object:grab_tag('boat')

        if object.is_closed then
            tables.water_polygon:add_row({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                geom = { create = 'area' }
            })
        else
            tables.water_line:add_row({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                geom = { create = 'line' }
            })
        end

    elseif object.tags.waterway then
        local osm_type = 'waterway'
        local osm_subtype = object:grab_tag('waterway')
        local name = object:grab_tag('name')
        local layer = parse_layer_value(object.tags.layer)
        local tunnel = object:grab_tag('tunnel')
        local bridge = object:grab_tag('bridge')
        local boat = object:grab_tag('boat')

        if object.is_closed then
            tables.water_polygon:add_row({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                geom = { create = 'area' }
            })
        else
            tables.water_line:add_row({
                osm_type = osm_type,
                osm_subtype = osm_subtype,
                name = name,
                layer = layer,
                tunnel = tunnel,
                bridge = bridge,
                boat = boat,
                geom = { create = 'line' }
            })
        end

    end

    
end


if osm2pgsql.process_node == nil then
    -- Change function name here
    osm2pgsql.process_node = water_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        water_process_node(object_copy)
    end
end



if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = water_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        water_process_way(object_copy)
    end
end
