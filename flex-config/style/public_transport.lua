require "helpers"

local tables = {}

tables.public_transport_point = osm2pgsql.define_table({
    name = 'public_transport_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = false },
        { column = 'public_transport',     type = 'text', not_null = true },
        { column = 'layer',   type = 'int', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'ref',     type = 'text' },
        { column = 'operator',     type = 'text' },
        { column = 'network',     type = 'text' },
        { column = 'surface',     type = 'text' },
        { column = 'bus',     type = 'text' },
        { column = 'shelter',     type = 'text' },
        { column = 'bench',     type = 'text' },
        { column = 'lit',     type = 'text' },
        { column = 'wheelchair', type = 'text'},
        { column = 'wheelchair_desc', type = 'text'},
        { column = 'geom',     type = 'point', projection = srid }
    }
})



tables.public_transport_line = osm2pgsql.define_table({
    name = 'public_transport_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = false },
        { column = 'public_transport',     type = 'text', not_null = true },
        { column = 'layer',   type = 'int', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'ref',     type = 'text' },
        { column = 'operator',     type = 'text' },
        { column = 'network',     type = 'text' },
        { column = 'surface',     type = 'text' },
        { column = 'bus',     type = 'text' },
        { column = 'shelter',     type = 'text' },
        { column = 'bench',     type = 'text' },
        { column = 'lit',     type = 'text' },
        { column = 'wheelchair', type = 'text'},
        { column = 'wheelchair_desc', type = 'text'},
        { column = 'geom',     type = 'linestring', projection = srid }
    }
})


tables.public_transport_polygon = osm2pgsql.define_table({
    name = 'public_transport_polygon',
    schema = schema_name,
    ids = { type = 'area', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = false },
        { column = 'public_transport',     type = 'text', not_null = true },
        { column = 'layer',   type = 'int', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'ref',     type = 'text' },
        { column = 'operator',     type = 'text' },
        { column = 'network',     type = 'text' },
        { column = 'surface',     type = 'text' },
        { column = 'bus',     type = 'text' },
        { column = 'shelter',     type = 'text' },
        { column = 'bench',     type = 'text' },
        { column = 'lit',     type = 'text' },
        { column = 'wheelchair', type = 'text'},
        { column = 'wheelchair_desc', type = 'text'},
        { column = 'geom',     type = 'multipolygon', projection = srid }
    }
})



local function get_osm_type_subtype(object)
    local osm_type_table = {}

    if object.tags.bus then
        osm_type_table['osm_type'] = 'bus'
        osm_type_table['osm_subtype'] = object.tags.bus
    elseif object.tags.railway then
        osm_type_table['osm_type'] = 'railway'
        osm_type_table['osm_subtype'] = object.tags.railway
    elseif object.tags.lightrail then
        osm_type_table['osm_type'] = 'lightrail'
        osm_type_table['osm_subtype'] = object.tags.lightrail
    elseif object.tags.train then
        osm_type_table['osm_type'] = 'train'
        osm_type_table['osm_subtype'] = object.tags.train
    elseif object.tags.aerialway then
        osm_type_table['osm_type'] = 'aerialway'
        osm_type_table['osm_subtype'] = object.tags.aerialway
    elseif object.tags.highway then
        osm_type_table['osm_type'] = 'highway'
        osm_type_table['osm_subtype'] = object.tags.highway
    else
        osm_type_table['osm_type'] = object.tags.public_transport
        if osm_type_table['osm_type'] == nil then
            osm_type_table['osm_type'] = 'unknown'
        end
        osm_type_table['osm_subtype'] = nil
    end

    return osm_type_table
end


local public_transport_first_level_keys = {
    'public_transport',
    'aerialway',
    'railway'
    -- NOTE: Bus is not included, duplicates data in `road*` layers
}


local is_first_level_public_transport = make_check_in_list_func(public_transport_first_level_keys)


local function public_transport_process_node(object)
    if not is_first_level_public_transport(object.tags)
            then
        return
    end

    local osm_types = get_osm_type_subtype(object)

    local public_transport = object.tags.public_transport
    if public_transport == nil then
        public_transport = 'other'
    end

    local name = get_name(object.tags)
    local ref = get_ref(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)
    local operator  = object.tags.operator
    local layer = parse_layer_value(object.tags.layer)

    local network = object.tags.network
    local surface = object.tags.surface
    local bus = object.tags.bus
    local shelter = object.tags.shelter
    local bench = object.tags.bench
    local lit = object.tags.lit

    tables.public_transport_point:add_row({
        osm_type = osm_types.osm_type,
        osm_subtype = osm_types.osm_subtype,
        public_transport = public_transport,
        name = name,
        ref = ref,
        operator = operator,
        layer = layer,
        network = network,
        surface = surface,
        bus = bus,
        shelter = shelter,
        bench = bench,
        lit = lit,
        wheelchair = wheelchair,
        wheelchair_desc = wheelchair_desc,
        geom = { create = 'point' }
    })

end


local function public_transport_process_way(object)
    if not is_first_level_public_transport(object.tags)
            then
        return
    end


    local osm_types = get_osm_type_subtype(object)

    local public_transport = object.tags.public_transport
    if public_transport == nil then
        public_transport = 'other'
    end

    local name = get_name(object.tags)
    local ref = get_ref(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)
    local operator  = object.tags.operator
    local layer = parse_layer_value(object.tags.layer)

    local network = object.tags.network
    local surface = object.tags.surface
    local bus = object.tags.bus
    local shelter = object.tags.shelter
    local bench = object.tags.bench
    local lit = object.tags.lit

    -- temporarily discarding polygons
    if (object.tags.area == 'yes' or object.is_closed)
            then
        tables.public_transport_polygon:add_row({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            public_transport = public_transport,
            name = name,
            ref = ref,
            operator = operator,
            layer = layer,
            network = network,
            surface = surface,
            bus = bus,
            shelter = shelter,
            bench = bench,
            lit = lit,
            wheelchair = wheelchair,
            wheelchair_desc = wheelchair_desc,
            geom = { create = 'area' }
        })
    else
        tables.public_transport_line:add_row({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            public_transport = public_transport,
            name = name,
            ref = ref,
            operator = operator,
            layer = layer,
            network = network,
            surface = surface,
            bus = bus,
            shelter = shelter,
            bench = bench,
            lit = lit,
            wheelchair = wheelchair,
            wheelchair_desc = wheelchair_desc,
            geom = { create = 'line' }
        })

    end

end



function public_transport_process_relation(object)
    if not is_first_level_public_transport(object.tags) then
        return
    end

    local osm_types = get_osm_type_subtype(object)

    local public_transport = object.tags.public_transport
    if public_transport == nil then
        public_transport = 'other'
    end

    local name = get_name(object.tags)
    local ref = get_ref(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)
    local operator  = object.tags.operator
    local layer = parse_layer_value(object.tags.layer)

    local network = object.tags.network
    local surface = object.tags.surface
    local bus = object.tags.bus
    local shelter = object.tags.shelter
    local bench = object.tags.bench
    local lit = object.tags.lit

    if object.tags.type == 'multipolygon' then
        tables.public_transport_polygon:add_row({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            public_transport = public_transport,
            name = name,
            ref = ref,
            operator = operator,
            layer = layer,
            network = network,
            surface = surface,
            bus = bus,
            shelter = shelter,
            bench = bench,
            lit = lit,
            wheelchair = wheelchair,
            wheelchair_desc = wheelchair_desc,
            geom = { create = 'area' }
        })
    end
end



if osm2pgsql.process_node == nil then
    -- Change function name here
    osm2pgsql.process_node = public_transport_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        public_transport_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    -- Change function name here
    osm2pgsql.process_way = public_transport_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        public_transport_process_way(object_copy)
    end
end



if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = public_transport_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        public_transport_process_relation(object_copy)
    end
end
