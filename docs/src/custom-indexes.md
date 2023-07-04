# Indexes

PgOSM Flex allows customizing all indexes, excluding the primary key.

> Setting indexes is only relevant for the first import.  When using `--replication` these configurations do not have any impact on indexes in the database.


Using custom indexes.


```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -v ~/git/pgosm-flex/flex-config/indexes/examples/noindexes:/app/flex-config/indexes \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```

## INI files

Each INI file under `flex-config/indexes/` should have 4 sections defined.
These sections must be defined in order to avoid error.  Technically only the
sections with matching calls to `get_indexes_from_spec()` in
`flex-config/helpers.lua` are required.  However, it is far clearer to just
say they're all required.


The simplest index specification file is shown below.  The four (4) empty 
sections define no indexes beyond the table's `PRIMARY KEY` on the `osm_id`
column.


```ini
[all]

[point]

[line]

[polygon]
```


There are three (3) variables that can be configured for each column in the
PgOSM Flex database.

* `<name>`
* `<name>_where`
* `<name>_method`

For example, the `admin_level` column can have a partial index created with
`admin_level=true` and `admin_level_where=admin_level IS NOT NULL`.

```ini
[all]
admin_level=true
admin_level_where=admin_level IS NOT NULL
```

## Spatial index method

To change the polygon index from `GIST` to `SPGIST` use the `geom_method`
option.  See Paul Ramsey's post
[(The Many) Spatial Indexes of PostGIS](https://www.crunchydata.com/blog/the-many-spatial-indexes-of-postgis)
for more information about when to choose `SPGIST`.



```ini
[point]
geom_method=spgist
```



## Most columns can be indexed

Defined in `flex_config/helpers.lua`.  See the definition of
`local index_columns = {...}`.



