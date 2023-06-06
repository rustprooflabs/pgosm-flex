require "helpers"
require "style.shop_helpers"

local tables = {}

tables.shop_combined_point = osm2pgsql.define_table({
    name = 'shop_combined_point',
    schema = schema_name,
    ids = { type = 'any', id_column = 'osm_id', type_column = 'geom_type' },
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
        { column = 'phone', type = 'text'},
        { column = 'wheelchair', type = 'text'},
        { column = 'wheelchair_desc', type = 'text'},
        { column = 'operator', type = 'text'},
        { column = 'brand', type = 'text'},
        { column = 'website', type = 'text'},
        { column = 'geom', type = 'point' , projection = srid, not_null = true },
    },
    indexes = {
        { column = 'geom', method = gist_type },
        { column = 'osm_type', method = 'btree' },
        { column = 'osm_subtype', method = 'btree', where = 'osm_subtype IS NOT NULL' },
    }
})



function shop_process_node_combined_point(object)
    if not is_first_level_shop(object.tags) then
        return
    end

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)
    local phone = object:grab_tag('phone')
    local operator  = object:grab_tag('operator')
    local brand  = object:grab_tag('brand')
    local website  = object:grab_tag('website')

    local osm_types = get_osm_type_subtype_shop(object)

    tables.shop_combined_point:insert({
        osm_type = osm_types.osm_type,
        osm_subtype = osm_types.osm_subtype,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        postcode = postcode,
        address = address,
        wheelchair = wheelchair,
        phone = phone,
        operator = operator,
        brand = brand,
        website = website,
        geom = object:as_point()
    })

end


function shop_process_way_combined_point(object)
    if not is_first_level_shop(object.tags) then
        return
    end

    local name = get_name(object.tags)
    local housenumber  = object.tags['addr:housenumber']
    local street = object.tags['addr:street']
    local city = object.tags['addr:city']
    local state = object.tags['addr:state']
    local postcode = object.tags['addr:postcode']
    local address = get_address(object.tags)
    local wheelchair = object.tags.wheelchair
    local wheelchair_desc = get_wheelchair_desc(object.tags)
    local phone = object:grab_tag('phone')
    local operator = object:grab_tag('operator')
    local brand = object:grab_tag('brand')
    local website = object:grab_tag('website')

    local osm_types = get_osm_type_subtype_shop(object)

    tables.shop_combined_point:insert({
        osm_type = osm_type,
        osm_subtype = osm_subtype,
        name = name,
        housenumber = housenumber,
        street = street,
        city = city,
        state = state,
        postcode = postcode,
        address = address,
        wheelchair = wheelchair,
        wheelchair_desc = wheelchair_desc,
        phone = phone,
        operator = operator,
        brand = brand,
        website = website,
        geom = object:as_polygon():centroid()
    })

end


if osm2pgsql.process_node == nil then
    osm2pgsql.process_node = shop_process_node_combined_point
else
    local nested = osm2pgsql.process_node
    osm2pgsql.process_node = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        shop_process_node_combined_point(object_copy)
    end
end


if osm2pgsql.process_way == nil then
    osm2pgsql.process_way = shop_process_way_combined_point
else
    local nested = osm2pgsql.process_way
    osm2pgsql.process_way = function(object)
        local object_copy = deep_copy(object)
        nested(object)
        shop_process_way_combined_point(object_copy)
    end
end
