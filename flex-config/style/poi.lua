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
    'natural'
}


local is_first_level_poi = make_check_in_list_func(poi_first_level_keys)


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

function building_poi(object)
    local bldg_name = get_name(object.tags)
    if (bldg_name ~= nil or object.tags.operator) then
        return true
    end

    return false
end





tables.poi_point = osm2pgsql.define_table({
    name = 'poi_point',
    schema = schema_name,
    ids = { type = 'node', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'operator', type = 'text'},
        { column = 'geom',     type = 'point' , projection = srid},
    }
})


tables.poi_line = osm2pgsql.define_table({
    name = 'poi_line',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'operator', type = 'text'},
        { column = 'geom',     type = 'linestring' , projection = srid},
    }
})

tables.poi_polygon = osm2pgsql.define_table({
    name = 'poi_polygon',
    schema = schema_name,
    ids = { type = 'way', id_column = 'osm_id' },
    columns = {
        { column = 'osm_type',     type = 'text', not_null = true },
        { column = 'osm_subtype',     type = 'text', not_null = true },
        { column = 'name',     type = 'text' },
        { column = 'housenumber', type = 'text'},
        { column = 'street',     type = 'text' },
        { column = 'city',     type = 'text' },
        { column = 'state', type = 'text'},
        { column = 'operator', type = 'text'},
        { column = 'geom',     type = 'multipolygon' , projection = srid},
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



    local name = get_name(object.tags)
    local housenumber  = object:grab_tag('addr:housenumber')
    local street = object:grab_tag('addr:street')
    local city = object:grab_tag('addr:city')
    local state = object:grab_tag('addr:state')
    local operator  = object:grab_tag('operator')

    local osm_type = nil
    local osm_subtype = nil

    if object.tags.shop then
        osm_type = 'shop'
        osm_subtype = object:grab_tag('shop')
    elseif object.tags.amenity then
        osm_type = 'amenity'
        osm_subtype = object:grab_tag('amenity')
    elseif object.tags.building then
        osm_type = 'building'
        osm_subtype = object:grab_tag('building')
    elseif object.tags.leisure then
        osm_type = 'leisure'
        osm_subtype = object:grab_tag('leisure')
    elseif object.tags.landuse then
        osm_type = 'landuse'
        osm_subtype = object:grab_tag('landuse')
    elseif object.tags.natural then
        osm_type = 'natural'
        osm_subtype = object:grab_tag('natural')
    elseif object.tags.man_made then
        osm_type = 'man_made'
        osm_subtype = object:grab_tag('man_made')
    elseif object.tags.tourism then
        osm_type = 'tourism'
        osm_subtype = object:grab_tag('tourism')
    else
        osm_type = 'Unknown'
        osm_subtype = 'Unknown'
    end

    tables.poi_point:add_row({
        osm_type = osm_type,
        osm_subtype = osm_subtype,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        operator = operator,
        geom = { create = 'point' }
    })



end



if osm2pgsql.process_node == nil then
    -- Change function name here
    osm2pgsql.process_node = poi_process_node
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        -- Change function name here
        poi_process_node(object_copy)
    end
end