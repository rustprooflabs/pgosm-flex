# Querying with PgOSM Flex

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



## Points of Interest (POIs)

PgOSM Flex loads an range of tags into a materialized view (`osm.poi_all`) for
easily searching POIs.
Line and polygon data is forced to point geometry using
`ST_Centroid()`.  This layer duplicates a bunch of other more specific layers
(shop, amenity, etc.) to provide a single place for simplified POI searches.

Special layer included by layer sets `run-all` and `run-no-tags`.
See `style/poi.lua` for logic on how to include POIs.
The topic of POIs is subject and likely is not inclusive of everything that probably should be considered
a POI. If there are POIs missing
from this table please submit a [new issue](https://github.com/rustprooflabs/pgosm-flex/issues/new)
with sufficient details about what is missing.
Pull requests also welcome! [See CONTRIBUTING.md](CONTRIBUTING.md).


Counts of POIs by `osm_type`.

```sql
SELECT osm_type, COUNT(*)
    FROM osm.vpoi_all
    GROUP BY osm_type
    ORDER BY COUNT(*) DESC;
```

Results from Washington D.C. subregion (March 2020).

```
┌──────────┬───────┐
│ osm_type │ count │
╞══════════╪═══════╡
│ amenity  │ 12663 │
│ leisure  │  2701 │
│ building │  2045 │
│ shop     │  1739 │
│ tourism  │   729 │
│ man_made │   570 │
│ landuse  │    32 │
│ natural  │    19 │
└──────────┴───────┘
```

Includes Points (`N`), Lines (`L`) and Polygons (`W`).


```sql
SELECT geom_type, COUNT(*) 
    FROM osm.vpoi_all
    GROUP BY geom_type
    ORDER BY COUNT(*) DESC;
```

```
┌───────────┬───────┐
│ geom_type │ count │
╞═══════════╪═══════╡
│ W         │ 10740 │
│ N         │  9556 │
│ L         │   202 │
└───────────┴───────┘
```

## Meta table

PgOSM Flex tracks processing metadata in the ``osm.pgosm_flex``  table. The initial import
has `osm2pgsql_mode = 'create'`, the subsequent update has
`osm2pgsql_mode = 'append'`. 


```sql
SELECT osm_date, region, srid,
        pgosm_flex_version, osm2pgsql_version, osm2pgsql_mode
    FROM osm.pgosm_flex
;
```

```bash
┌────────────┬───────────────────────────┬──────┬────────────────────┬───────────────────┬────────────────┐
│  osm_date  │          region           │ srid │ pgosm_flex_version │ osm2pgsql_version │ osm2pgsql_mode │
╞════════════╪═══════════════════════════╪══════╪════════════════════╪═══════════════════╪════════════════╡
│ 2022-11-04 │ north-america/us-colorado │ 3857 │ 0.6.2-e1f140f      │ 1.7.2             │ create         │
│ 2022-11-25 │ north-america/us-colorado │ 3857 │ 0.6.2-e1f140f      │ 1.7.2             │ append         │
└────────────┴───────────────────────────┴──────┴────────────────────┴───────────────────┴────────────────┘
```
