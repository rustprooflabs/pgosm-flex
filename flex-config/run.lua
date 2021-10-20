local inifile = require('inifile')


conf = inifile.parse('default.ini')


require "style.pgosm-meta"


if conf['layerset']['road'] then
    print('Including road')
    require "style.road"
end

if conf['layerset']['road_major'] then
    print('Including road_major')
    require "style.road_major"
end

if conf['layerset']['tags'] then
    print('Including tags')
    require "style.tags"
end

if conf['layerset']['unitable'] then
    print('Including unitable')
    require "style.unitable"
end


