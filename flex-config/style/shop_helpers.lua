
function get_osm_type_subtype_shop(object)
    local osm_type_table = {}

    if object.tags.shop then
        osm_type_table['osm_type'] = 'shop'
        osm_type_table['osm_subtype'] = object:grab_tag('shop')
    -- This creates overlap between this layer and amenity layer
    elseif object.tags.amenity == 'vending_machine'
            or object.tags.amenity == 'car_rental'
            or object.tags.amenity == 'motorcycle_rental'
            or object.tags.amenity == 'cafe'
            or object.tags.amenity == 'phone_repair'
            or object.tags.amenity == 'music_school'
            or object.tags.amenity == 'pub'
            or object.tags.amenity == 'pharmacy'
            or object.tags.amenity == 'ticket_booth'
            or object.tags.amenity == 'shop'
            then
        osm_type_table['osm_type'] = 'amenity'
        osm_type_table['osm_subtype'] = object:grab_tag('amenity')
    end

    return osm_type_table
end

local shop_first_level_keys = {
    'shop',
    'amenity'
}

is_first_level_shop = make_check_in_list_func(shop_first_level_keys)

