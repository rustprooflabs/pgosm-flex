-- Used by PgOSM Flex run scripts to load layerset configuration
local inifile = require('inifile')

local pgosm_layerset_env = os.getenv("PGOSM_LAYERSET")
local pgosm_layerset_path_env = os.getenv("PGOSM_LAYERSET_PATH")
local pgosm_layerset = nil
local pgosm_layerset_path = nil

local ext = '.ini'

if pgosm_layerset_env then
    pgosm_layerset = pgosm_layerset_env
else
    pgosm_layerset = 'default'
end

if pgosm_layerset_path_env then
    pgosm_layerset_path = pgosm_layerset_path_env
    print('Layerset INI path set to ' .. pgosm_layerset_path)
else
    print('Using default layerset INI path')
    pgosm_layerset_path = 'layerset/'
end


local layerset_file = pgosm_layerset_path .. pgosm_layerset .. ext
print('Loading config: ' .. layerset_file)
conf = inifile.parse(layerset_file)
