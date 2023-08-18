-- Loads the `conf` var from layerset INI file
require "layerset"

local driver = require('luasql.postgres')
local env = driver.postgres()

local pgosm_conn_env = os.getenv("PGOSM_CONN")
local pgosm_conn = nil

if pgosm_conn_env then
    pgosm_conn = pgosm_conn_env
else
    error('Environment variable PGOSM_CONN must be set.')
end

local schema_name_env = os.getenv("SCHEMA_NAME")
local schema_name = nil

if schema_name_env then
    schema_name = schema_name_env
else
    error('Environment variable SCHEMA_NAME must be set.')
end


layers = {'amenity', 'building', 'building_combined_point', 'indoor'
          , 'infrastructure', 'landuse', 'leisure'
          , 'natural', 'place', 'poi', 'public_transport'
          , 'road', 'road_major', 'shop', 'shop_combined_point', 'tags'
          , 'traffic', 'unitable', 'water'}


local function post_processing(layerset)
    print(string.format('Post-processing %s', layerset))
    local filename = string.format('sql/%s.sql', layerset)
    local sql_file = io.open(filename, 'r')
    sql_raw = sql_file:read( '*all' )
    sql_file:close()
    sql_raw = sql_raw:gsub('osm%.', schema_name .. '.')
    local result = con:execute(sql_raw)

    -- Returns 0 on success, nil on error.
    if result == nil then
        print(string.format("Error in post-processing layerset: %s", layerset))
        return false
    end

    return true
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

local errors = 0

for ix, layer in ipairs(layers) do
    if conf['layerset'][layer] then
        if not post_processing(layer) then
            errors = errors + 1
        end
    end
end


-- close everything
cur:close()
con:close()
env:close()

if errors > 0 then
    os.exit(1)
end
