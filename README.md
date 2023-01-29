# PgOSM Flex

> DOCUMENTATION BEING REMOVED FROM HERE as it's moved into the doc book.  The final version on this page will be greatly simplified.

## Layer Sets


PgOSM Flex includes a few layersets and makes it easy to customize your own.
See [docs/LAYERSETS.md](docs/LAYERSETS.md) for details.



## QGIS Layer Styles

If you use QGIS to visualize OpenStreetMap, there are a few basic
styles using the `public.layer_styles` table created by QGIS.
This data is loaded by default and can be excluded with `--data-only`.

See [the QGIS Style README.md](https://github.com/rustprooflabs/pgosm-flex/blob/main/db/qgis-style/README.md)
for more information.


## Explore data loaded

A peek at some of the tables loaded.
This query requires the
[PostgreSQL Data Dictionary (PgDD) extension](https://github.com/rustprooflabs/pgdd),
use `\dt+ osm.*` in `psql` for similar details.


```sql
SELECT s_name, t_name, rows, size_plus_indexes 
    FROM dd.tables 
    WHERE s_name = 'osm' 
    ORDER BY t_name LIMIT 10;
```

```bash
    ┌────────┬──────────────────────┬────────┬───────────────────┐
    │ s_name │        t_name        │  rows  │ size_plus_indexes │
    ╞════════╪══════════════════════╪════════╪═══════════════════╡
    │ osm    │ amenity_line         │      7 │ 56 kB             │
    │ osm    │ amenity_point        │   5796 │ 1136 kB           │
    │ osm    │ amenity_polygon      │   7593 │ 3704 kB           │
    │ osm    │ building_point       │    525 │ 128 kB            │
    │ osm    │ building_polygon     │ 161256 │ 55 MB             │
    │ osm    │ indoor_line          │      1 │ 40 kB             │
    │ osm    │ indoor_point         │      5 │ 40 kB             │
    │ osm    │ indoor_polygon       │    288 │ 136 kB            │
    │ osm    │ infrastructure_point │    884 │ 216 kB            │
    │ osm    │ landuse_point        │     18 │ 56 kB             │
    └────────┴──────────────────────┴────────┴───────────────────┘
```




## Query examples

For example queries with data loaded by PgOSM-Flex see
[docs/QUERY.md](docs/QUERY.md).



## One table to rule them all

From the perspective of database design, the `osm.unitable` option is the **worst**!
This table violates all sorts of best practices established in this project
by shoving all features into a single unstructured table.

> This style included in PgOSM Flex is intended to be used for troubleshooting and quality control.  It is not intended to be used for real production workloads! This table is helpful for exploring the full data set when you don't really know what you are looking for, but you know **where** you are looking.

Unitable is loaded with the `everything` layerset.  Feel free to create your own
customized layerset if needed.



```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --layerset=everything
```


> The `unitable.lua` script include in in this project was [adapted from the unitable example from osm2pgsql](https://github.com/openstreetmap/osm2pgsql/blob/master/flex-config/unitable.lua). This version uses JSONB instead of HSTORE and takes advantage of `helpers.lua` to easily customize SRID.


## JSONB support

PgOSM-Flex uses `JSONB` in Postgres to store the raw OpenStreetMap
key/value data (`tags` column) and relation members (`member_ids`).
The `tags` column only exists in the `osm.tags` and `osm.unitable` tables.
The `member_ids` column is included in:

* `osm.place_polygon`
* `osm.poi_polygon`
* `osm.public_transport_line`
* `osm.public_transport_polygon`
* `osm.road_line`
* `osm.road_major`
* `osm.road_polygon`




## Projects using PgOSM Flex


See the listing of known [projects using PgOSM Flex](docs/PROJECTS.md).


## Additional resources


Blog posts covering various details and background information.

* [Better OpenStreetMap places in PostGIS](https://blog.rustprooflabs.com/2021/01/pgosm-flex-improved-openstreetmap-places-postgis)
* [Improved OpenStreetMap data structure in PostGIS](https://blog.rustprooflabs.com/2021/01/postgis-openstreetmap-flex-structure) 
* [Hands on with osm2pgsql's new Flex output](https://blog.rustprooflabs.com/2020/12/osm2gpsql-flex-output-to-postgis).
