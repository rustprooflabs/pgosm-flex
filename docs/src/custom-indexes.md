# Indexes

PgOSM Flex allows customizing all indexes using `.ini` files stored under
`flex-config/indexes/`.  The default indexing strategy is baked into the Docker
image, to use the defaults you can follow the instructions throughout the documentation
without any adjustments.

To customize indexes map the path of your custom index definitions folder
to the Docker container under `/app/flex-config/indexes`.  This overwrites the default
indexing scheme with the custom folder.
The following command assumes you have the PgOSM Flex project cloned into the
`~/git/pgosm-flex` folder.  The `noindexes` example creates the PgOSM Flex
tables with indexes beyond the required `PRIMARY KEY`s.

```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -v ~/git/pgosm-flex/flex-config/indexes/examples/noindexes:/app/flex-config/indexes \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```


## Caveats


Setting indexes is only relevant for the first import.  When using `--replication`
these configurations only impact the initial import. Subsequent imports make no
attempt to verify / adjust database indexes.

The primary key cannot be omitted using this approach.  The primary keys on
`osm_id` are created in post-processing SQL and is not able to be overridden
using this approach.


## INI files

Each Lua style (`flex-config/style/*.lua`) must have a matching INI file
under `flex-config/indexes/`.  Each `.ini` file should have 4 sections defined.


```ini
[all]

[point]

[line]

[polygon]
```


The simplest index specification file is shown above by defining the four (4)
empty sections define no indexes beyond the table's `PRIMARY KEY` on the `osm_id`
column.

## Index variables

There are three (3) variables that can be configured for each column in the
PgOSM Flex database.

* `<name>`
* `<name>_where`
* `<name>_method`

### To index or not to index

The `<name>` variable is the column's name and is set to boolean.
To add an index to the `admin_level` column add `admin_level=true`.  To exclude
an index from a column either omit the column from the definition file, or
set it to `false`, e.g. `admin_level=false`.

### Partial indexes


Partial indexes can be created with the `<name>_where` variable.
The `admin_level` column can have a partial index created on rows where the
`admin_level` value is set using `admin_level_where=admin_level IS NOT NULL`.

```ini
[all]
admin_level=true
admin_level_where=admin_level IS NOT NULL
```

## Index method

The `<name>_method` variable can be used to set the index method used by Postgres.
One way to use this is to change a spatial column's index from 
`GIST` to `SPGIST`, via `geom_method=spgist`.




```ini
[point]
geom=true
geom_method=spgist
```

> See Paul Ramsey's post [(The Many) Spatial Indexes of PostGIS](https://www.crunchydata.com/blog/the-many-spatial-indexes-of-postgis) for more information about when to choose `SPGIST`.


Setting index method isn't limited to spatial indexes. The following example
illustrates adding a `BRIN` index to the `admin_level` column.

```ini
[all]
admin_level=true
admin_level_method=brin
```


## Most columns can be indexed

Defined in `flex_config/helpers.lua`.  See the definition of
`local index_columns = {...}`.



