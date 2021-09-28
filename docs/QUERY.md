# Querying with PgOSM-Flex


## Places

Use the `osm.vplace_polygon` view for most uses.  When a relation exists along with multiple polygon
parts, the view removes the non-relation polygons and only keeps the relation.

[Commerce City, Colorado, relation 112806](https://www.openstreetmap.org/relation/112806)
has 84 members as of 1/13/2021.  The view only returns one row when searching by name.

```sql
SELECT COUNT(*)
    FROM osm.vplace_polygon
    WHERE name = 'Commerce City'
;
```

```bash
count|
-----|
    1|
```


When querying the base table by name, 52 rows are returned.

```sql
SELECT COUNT(*)
    FROM osm.place_polygon
    WHERE name = 'Commerce City'
;
```



```bash
count|
-----|
   52|
```


> Note: The count here is different than in OpenStreetMap.org because this is only looking at polygons.  The OpenStreetMap.org view also includes nodes and lines where this query does not.


## Nested admin polygons

Nested admin polygons are stored in the table `osm.place_polygon_nested`.
The `osm.build_nested_admin_polygons()` to populate the table is defined in `flex-config/place.sql`,
the Docker process automatically runs it.
Can run quickly on small areas (Colorado), takes significantly longer on larger
areas (North America).


The Python script in the Docker image has a `--skip-nested` option to skip
running the function to populate the table.  It can always be populated
at a later time manually using the function.

```sql
CALL osm.build_nested_admin_polygons();
```

When this process is running for a while it can be monitored with this query.

```sql
SELECT COUNT(*) AS row_count,
        COUNT(*) FILTER (WHERE nest_level IS NOT NULL) AS rows_processed
    FROM osm.place_polygon_nested
;
```




# Quality Control Queries

## Features not Loaded

The process of selectively load specific features and not others always has the chance
of accidentally missing important data.

Running and examine tags from the SQL script `db/qc/features_not_in_run_all.sql`.
Run within `psql` (using `\i db/qc/features_not_in_run_all.sql`) or a GUI client
to explore the temp table used to return the aggregated results, `osm_missing`.
The table is a `TEMP TABLE` so will disappear when the session ends.

Example results from initial run (v0.0.4) showed some obvious omissions from the
current layer definitions.

```bash
┌────────────────────────────────────────┬────────┐
│           jsonb_object_keys            │ count  │
╞════════════════════════════════════════╪════════╡
│ landuse                                │ 110965 │
│ addr:street                            │  89482 │
│ addr:housenumber                       │  89210 │
│ name                                   │  47151 │
│ leisure                                │  25351 │
│ addr:state                             │  19051 │
│ power                                  │  16933 │
│ addr:unit                              │  13973 │
│ building:part                          │  13773 │
│ golf                                   │  13427 │
│ railway                                │  13032 │
│ addr:city                              │  12426 │
│ addr:postcode                          │  12358 │
│ height                                 │  12113 │
│ building:colour                        │  11124 │
│ roof:colour                            │  11115 │
```

## Unroutable routes

The `helpers.lua` methods are probably not perfect.

* `routable_foot()`
* `routable_cycle()`
* `routable_motor()`



```sql
SELECT * FROM osm.road_line
    WHERE NOT route_foot AND NOT route_motor AND NOT route_cycle
;
```
> Not all rows returned are errors.  `highway = 'construction'` is not necessarily determinate...


## Relations missing from unitable

```sql
SELECT t.*
    FROM osm.tags t
    WHERE t.geom_type = 'R' 
        AND NOT EXISTS (
            SELECT 1
            FROM osm.unitable u
            WHERE u.geom_type = t.geom_type AND t.osm_id = u.osm_id
);
```


