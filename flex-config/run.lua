local inifile = require('inifile')


local pgosm_config_env = os.getenv("PGOSM_CONFIG")
local pgosm_config = nil

if pgosm_config_env then
    pgosm_config = pgosm_config_env
else
    pgosm_config = 'default'
end

local layerset_path = 'layerset/' .. pgosm_config .. '.ini'
print('Loading config: ' .. layerset_path)
conf = inifile.parse(layerset_path)


require "style.pgosm-meta"


if conf['layerset']['amenity'] then
    print('Including amenity')
    require "style.amenity"
end

if conf['layerset']['building'] then
    print('Including building')
    require "style.building"
end

if conf['layerset']['indoor'] then
    print('Including indoor')
    require "style.indoor"
end

if conf['layerset']['infrastructure'] then
    print('Including infrastructure')
    require "style.infrastructure"
end

if conf['layerset']['landuse'] then
    print('Including landuse')
    require "style.landuse"
end

if conf['layerset']['leisure'] then
    print('Including leisure')
    require "style.leisure"
end

if conf['layerset']['natural'] then
    print('Including natural')
    require "style.natural"
end

if conf['layerset']['place'] then
    print('Including place')
    require "style.place"
end

if conf['layerset']['poi'] then
    print('Including poi')
    require "style.poi"
end

if conf['layerset']['public_transport'] then
    print('Including public_transport')
    require "style.public_transport"
end

if conf['layerset']['road'] then
    print('Including road')
    require "style.road"
end

if conf['layerset']['road_major'] then
    print('Including road_major')
    require "style.road_major"
end

if conf['layerset']['shop'] then
    print('Including shop')
    require "style.shop"
end

if conf['layerset']['tags'] then
    print('Including tags')
    require "style.tags"
end

if conf['layerset']['traffic'] then
    print('Including traffic')
    require "style.traffic"
end

if conf['layerset']['unitable'] then
    print('Including unitable')
    require "style.unitable"
end

if conf['layerset']['water'] then
    print('Including water')
    require "style.water"
end

