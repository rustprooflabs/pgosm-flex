# Routing with PgOSM Flex

This page provides a simple example of using OpenStreetMap roads
loaded with PgOSM Flex for routing.
The example uses the D.C. PBF included under `tests/data/`.
This specific data source is chosen to provide a consistent input
for predictable results.  Even with using the same data and the
same code, some steps will have minor differences. These differences
are mentioned in those sections.

```bash
cd ~/pgosm-data

wget https://github.com/rustprooflabs/pgosm-flex/raw/main/tests/data/district-of-columbia-2021-01-13.osm.pbf
wget https://github.com/rustprooflabs/pgosm-flex/raw/main/tests/data/district-of-columbia-2021-01-13.osm.pbf.md5
```

Run `docker exec` to load the District of Columbia file from
January 13, 2021.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --pgosm-date=2021-01-13
```


## Prepare for routing

Create the `pgrouting` extension if it does not already exist.
Also create the `routing` schema to store the data used in this
example.


```sql
CREATE EXTENSION IF NOT EXISTS pgrouting;
CREATE SCHEMA IF NOT EXISTS routing;
```



### Clean the data

Prepare roads for routing using `pgrouting`` functions.  The bulk of
the following code is removing multi-linestrings which cause errors
with pgRouting.

```sql
CREATE TABLE routing.road_line AS
WITH a AS (
-- Remove as many multi-linestrings as possible with ST_LineMerge() 
SELECT osm_id, osm_type, maxspeed, oneway, layer,
        route_foot, route_cycle, route_motor, access,
        ST_LineMerge(geom) AS geom
    FROM osm.road_line
), extra_cleanup AS (
-- Pull out those that are still multi, use ST_Dump() to pull out parts
SELECT osm_id, osm_type, maxspeed, oneway, layer,
        route_foot, route_cycle, route_motor, access,
        (ST_Dump(geom)).geom AS geom
    FROM a 
    WHERE ST_GeometryType(geom) = 'ST_MultiLineString'
), combined AS (
-- Combine two sources
SELECT osm_id, osm_type, maxspeed, oneway, layer,
        route_foot, route_cycle, route_motor, access,
        geom
    FROM a
    WHERE ST_GeometryType(geom) != 'ST_MultiLineString'
UNION
SELECT osm_id, osm_type, maxspeed, oneway, layer,
        route_foot, route_cycle, route_motor, access,
        geom
    FROM extra_cleanup
    -- Some data may be lost here if multi-linestring somehow
    -- persists through the extra_cleanup query
    WHERE ST_GeometryType(geom) != 'ST_MultiLineString'
)
-- Calculate a new surrogate ID for key
SELECT ROW_NUMBER() OVER (ORDER BY geom) AS id, *
    FROM combined
    ORDER BY geom
;
```

The above query creates the `routing.road_line` table.  The next step
adds some database best practices to the table:

* Explain why a surrogate ID was added
* Primary key on the `id` column
* Index on `osm_id`


```sql
COMMENT ON COLUMN routing.road_line.id IS 'Surrogate ID, cannot rely on osm_id being unique after converting multi-linestrings to linestrings.';
ALTER TABLE routing.road_line
    ADD CONSTRAINT pk_routing_road_line PRIMARY KEY (id)
;
CREATE INDEX ix_routing_road_line_osm_id
    ON routing.road_line (osm_id)
;
```

### Prepare data for routing

The [pgRouting 4.0 release](https://github.com/pgRouting/pgrouting/releases/tag/v4.0.0)
removed functions previously used for this step.
The remainder of the instructions are scoped to which version of pgRouting you are
using.

Check via:

```sql
SELECT * FROM pgr_version();
```

The 4.0 instructions are attempting to improve naming conventions for improved
understanding and usability.
The pre-4.0 version uses different naming conventions mostly conforming
to naming conventions of the legacy functions. 


Follow the instructions for your version of pgRouting.

* [Routing with pgRouting 3](./routing-3.md)
* [Routing with pgRouting 4](./routing-4.md)


> PgOSM Flex 1.1.1 and later packages `pgRouting` 4.0.
> If you are using external Postgres
> as the target for your data, the pgRouting version you have installed is in
> your control.



