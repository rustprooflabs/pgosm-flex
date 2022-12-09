require "helpers"

local tables = {}

-- Keys to include for further checking.  Not all values from each key will be preserved
local poi_first_level_keys = {
    'building',
    'shop',
    'amenity',
    'leisure',
    'man_made',
    'tourism',
    'landuse',
    'natural',
    'historic'
}

local is_first_level_poi = make_check_in_list_func(poi_first_level_keys)


function building_poi(object)
    local bldg_name = get_name(object.tags)
    if (bldg_name ~= '' or object.tags.operator) then
        return true
    end

    return false
end


function landuse_poi(object)
    if (object.tags.landuse == 'cemetery'
            or object.tags.landuse == 'orchard'
            or object.tags.landuse == 'railway'
            or object.tags.landuse == 'village_green'
            or object.tags.landuse == 'vineyard') then
        return true
    end

    return false

end


function man_made_poi(object)
    if (object.tags.man_made == 'beacon'
            or object.tags.man_made == 'chimney'
            or object.tags.man_made == 'communications_tower'
            or object.tags.man_made == 'crane'
            or object.tags.man_made == 'flagpole'
            or object.tags.man_made == 'lighthouse'
            or object.tags.man_made == 'mast'
            or object.tags.man_made == 'obelisk'
            or object.tags.man_made == 'observatory'
            or object.tags.man_made == 'offshore_platform'
            or object.tags.man_made == 'pier'
            or object.tags.man_made == 'silo'
            or object.tags.man_made == 'survey_point'
            or object.tags.man_made == 'telescope'
            or object.tags.man_made == 'tower'
            or object.tags.man_made == 'water_tap'
            or object.tags.man_made == 'water_tower'
            or object.tags.man_made == 'water_well'
            or object.tags.man_made == 'windmill'
            or object.tags.man_made == 'works'
            ) then
        return true
    end

    return false
end

function natural_poi(object)
    if (object.tags.natural == 'peak'
            or object.tags.natural == 'glacier'
            or object.tags.natural == 'reef'
            or object.tags.natural == 'hot_spring'
            or object.tags.natural == 'bay') then
        return true
    end

    return false
end


local function get_osm_type_subtype(object)
    local osm_type_table = {}

    if object.tags.shop then
        osm_type_table['osm_type'] = 'shop'
        osm_type_table['osm_subtype'] = object:grab_tag('shop')
    elseif object.tags.amenity then
        osm_type_table['osm_type'] = 'amenity'
        osm_type_table['osm_subtype'] = object:grab_tag('amenity')
    elseif object.tags.building then
        osm_type_table['osm_type'] = 'building'
        osm_type_table['osm_subtype'] = object:grab_tag('building')
    elseif object.tags.leisure then
        osm_type_table['osm_type'] = 'leisure'
        osm_type_table['osm_subtype'] = object:grab_tag('leisure')
    elseif object.tags.landuse then
        osm_type_table['osm_type'] = 'landuse'
        osm_type_table['osm_subtype'] = object:grab_tag('landuse')
    elseif object.tags.natural then
        osm_type_table['osm_type'] = 'natural'
        osm_type_table['osm_subtype'] = object:grab_tag('natural')
    elseif object.tags.man_made then
        osm_type_table['osm_type'] = 'man_made'
        osm_type_table['osm_subtype'] = object:grab_tag('man_made')
    elseif object.tags.tourism then
        osm_type_table['osm_type'] = 'tourism'
        osm_type_table['osm_subtype'] = object:grab_tag('tourism')
    elseif object.tags.historic then
        osm_type_table['osm_type'] = 'historic'
        osm_type_table['osm_subtype'] = object.tags['historic']
    else
        -- Cannot be NULL
        osm_type_table['osm_type'] = 'Unknown'
        osm_type_table['osm_subtype'] = 'Unknown'
    end

    return osm_type_table
end


tables.poi_point = osm2pgsql.define_table({
    name = 'poi_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street', type = 'text' },
        { column = 'city', type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'operator', type = 'text'},
        { column = 'geom', type = 'point', projection = srid, not_null = true},
    },
    indexes = {
        { column = 'geom', method = 'gist' },
        { column = 'osm_type', method = 'btree' },
        { column = 'osm_subtype', method = 'btree', where = 'osm_subtype IS NOT NULL ' },
    }
})


tables.poi_line = osm2pgsql.define_table({
    name = 'poi_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street', type = 'text' },
        { column = 'city', type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'operator', type = 'text'},
        { column = 'geom', type = 'linestring', projection = srid, not_null = true},
    },
    indexes = {
        { column = 'geom', method = 'gist' },
        { column = 'osm_type', method = 'btree' },
        { column = 'osm_subtype', method = 'btree', where = 'osm_subtype IS NOT NULL ' },
    }
})

tables.poi_polygon = osm2pgsql.define_table({
    name = 'poi_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type', type = 'text', not_null = true },
        { column = 'osm_subtype', type = 'text', not_null = true },
        { column = 'name', type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street', type = 'text' },
        { column = 'city', type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'postcode', type = 'text'},
        { column = 'address', type = 'text', not_null = true},
        { column = 'operator', type = 'text'},
        { column = 'member_ids', type = 'jsonb'},
        { column = 'geom', type = 'multipolygon', projection = srid, not_null = true},
    },
    indexes = {
        { column = 'geom', method = 'gist' },
        { column = 'osm_type', method = 'btree' },
        { column = 'osm_subtype', method = 'btree', where = 'osm_subtype IS NOT NULL ' },
    }
})



function poi_process_node(object)
    -- Quickly remove any that don't match the 1st level of checks
    if not is_first_level_poi(object.tags) then
        return
    end

    if (object.tags.natural and not natural_poi(object)) then
        return
    end

    if (object.tags.landuse and not landuse_poi(object)) then
        return
    end

    if (object.tags.building and not building_poi(object)) then
        return
    end


    if (object.tags.man_made and not man_made_poi(object)) then
        return
    end


    local osm_types = get_osm_type_subtype(object)

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)

    local operator  = object:grab_tag('operator')

    tables.poi_point:insert({
        osm_type = osm_types.osm_type,
        osm_subtype = osm_types.osm_subtype,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        postcode = postcode,
        address = address,
        operator = operator,
        geom = object:as_point()
    })

end


function poi_process_way(object)
    -- Quickly remove any that don't match the 1st level of checks
    if not is_first_level_poi(object.tags) then
        return
    end

    -- Deeper checks for specific osm_type details
    if (object.tags.natural and not natural_poi(object)) then
        return
    end

    if (object.tags.landuse and not landuse_poi(object)) then
        return
    end

    if (object.tags.building and not building_poi(object)) then
        return
    end

    if (object.tags.man_made and not man_made_poi(object)) then
        return
    end

    local osm_types = get_osm_type_subtype(object)

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local operator  = object:grab_tag('operator')

    if object.is_closed then

        tables.poi_polygon:insert({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            operator = operator,
            geom = object:as_polygon()
        })
    else
        tables.poi_line:insert({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            operator = operator,
            geom = object:as_multilinestring()
        })
    end

end



function poi_process_relation(object)
    -- Quickly remove any that don't match the 1st level of checks
    if not is_first_level_poi(object.tags) then
        return
    end

    -- Deeper checks for specific osm_type details
    if (object.tags.natural and not natural_poi(object)) then
        return
    end

    if (object.tags.landuse and not landuse_poi(object)) then
        return
    end

    if (object.tags.building and not building_poi(object)) then
        return
    end

    if (object.tags.man_made and not man_made_poi(object)) then
        return
    end

    -- Gets osm_type and osm_subtype
    local osm_types = get_osm_type_subtype(object)

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local operator  = object:grab_tag('operator')

    local member_ids = osm2pgsql.way_member_ids(object)

    if object.tags.type == 'multipolygon' or object.tags.type == 'boundary' then
        tables.poi_polygon:insert({
            osm_type = osm_types.osm_type,
            osm_subtype = osm_types.osm_subtype,
            name = name,
            housenumber = housenumber,
            street = street,
            city = city,
            state = state,
            postcode = postcode,
            address = address,
            operator = operator,
            member_ids = member_ids,
            geom = object:as_multipolygon()
        })
    end

end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = poi_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        poi_process_node(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = poi_process_way
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        poi_process_way(object_copy)
    end
end


if osm2pgsql.process_relation == nil then
    osm2pgsql.process_relation = poi_process_relation
else
    local nested = osm2pgsql.process_relation
    osm2pgsql.process_relation = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        poi_process_relation(object_copy)
    end
end

