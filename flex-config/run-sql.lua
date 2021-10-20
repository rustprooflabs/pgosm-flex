local inifile = require('inifile')
local driver = require('luasql.postgres')
local env = driver.postgres()

local pgosm_conn_env = os.getenv("PGOSM_CONN")
local pgosm_conn = nil

if pgosm_conn_env then
    pgosm_conn = pgosm_conn_env
else
    error('ENV VAR PGOSM_CONN must be set.')
end

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


local function post_processing(layerset)
	print(string.format('Post-processing %s', layerset))
	local filename = string.format('sql/%s.sql', layerset)
    local sql_file = io.open(filename, 'r')
    sql_raw = sql_file:read( '*all' )
    sql_file:close()
    local result = con:execute(sql_raw)
    --print(result) -- Returns 0.0 on success?  nil on error?
end



-- Establish connection to Postgres
con = assert (env:connect(pgosm_conn))

-- simple query to verify connection
cur = con:execute"SELECT version() AS pg_version;"

row = cur:fetch ({}, "a")
while row do
  print(string.format("Postgres version: %s", row.pg_version))
  -- reusing the table of results
  row = cur:fetch (row, "a")
end


post_processing('pgosm-meta')

if conf['layerset']['amenity'] then
    post_processing('amenity')
end

if conf['layerset']['building'] then
    post_processing('building')
end

if conf['layerset']['indoor'] then
    post_processing('indoor')
end

if conf['layerset']['infrastructure'] then
    post_processing('infrastructure')
end

if conf['layerset']['landuse'] then
    post_processing('landuse')
end

if conf['layerset']['leisure'] then
    post_processing('leisure')
end

if conf['layerset']['natural'] then
    post_processing('natural')
end

if conf['layerset']['place'] then
    post_processing('place')
end

if conf['layerset']['poi'] then
    post_processing('poi')
end

if conf['layerset']['public_transport'] then
    post_processing('public_transport')
end

if conf['layerset']['road'] then
    post_processing('road')
end

if conf['layerset']['road_major'] then
    post_processing('road_major')
end

if conf['layerset']['shop'] then
    post_processing('shop')
end

if conf['layerset']['tags'] then
    post_processing('tags')
end

if conf['layerset']['traffic'] then
    post_processing('traffic')
end

if conf['layerset']['unitable'] then
    post_processing('unitable')
end

if conf['layerset']['water'] then
    post_processing('water')
end


-- close everything
cur:close()
con:close()
env:close()
