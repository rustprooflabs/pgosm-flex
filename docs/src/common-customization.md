# Common Customizations

A major goal of PgOSM Flex is support a wide range of use cases for using
OpenStreetMap data in PostGIS. This chapter explores a few ways PgOSM Flex
can be customized.


## Selecting region and subregion

The most used customization is the region and subregion selection.
The examples throughout this project's documentation use
the `--region=north-america/us` and `--subregion=district-of-columbia`
because it is a small region that downloads and imports quickly.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```

By default PgOSM Flex will attempt to download the necessary data files
from [Geofabrik's download server](https://download.geofabrik.de/).
Navigate the Region/Sub-region structure on Geofabrik to determine
exactly what `--region` and `--subregion` options to choose.
This can be a bit confusing as larger subregions can contain smaller subregions.
Feel free to [start a discussion](https://github.com/rustprooflabs/pgosm-flex/discussions/new/choose) if you need help figuring this part out!

If you want to load the entire United States subregion, instead of
the District of Columbia subregion, the `docker exec` command is changed to the
following.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america \
    --subregion=us
```

For top-level regions, such as North America, leave off the `--subregion` option.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america
```

## Specific input file

The automatic Geofabrik download can be overridden by providing PgOSM Flex
with the path to a valid `.osm.pbf` file using `--input-file`.
This option overrides the default file handling, archiving, and MD5
checksum validation.  With `--input-file` you can use a custom `osm.pbf`
you created, or use it to simply remove the need for an internet connection
from the instance running the processing.

> Note: The `--region` option is always required, the `--subregion` option can be used with `--input-file` to put the information in the `subregion` column of `osm.pgosm_flex`.


## Customize load to PostGIS

There are a few ways to customize exactly how data is loaded to PostGIS / Postgres.

### SRID

PgOSM Flex defaults to SRID 3857 matching the default osm2pgsql behavior.
This can be customized using `--srid 4326` or any other SRID supported by
osm2pgsql and PostGIS. 



### Language

The `--language` option enables defining a preferred language for OpenStreetMap
names.  If `--language=en` is defined, PgOSM Flex's `helper.get_name()`
function will use `name:en` if it exists.  The usage and effect
of this option is shown in [this comment](https://github.com/rustprooflabs/pgosm-flex/issues/93#issuecomment-818271870).

Using `-e PGOSM_LANGUAGE=kn` for U.S. West results in most state labels picking
up the Kannada language option.  The states without a `name:kn` default
to the standard name selection logic.

![](https://user-images.githubusercontent.com/3085224/114467942-ecd29700-9ba7-11eb-980a-10a127fd3c97.png)



### Data only

The `--data-only` option skips creating optional data structures in the target
database.  This includes the helper tables in the `pgosm` schema and the 
QGIS layer style table.




## Skip nested place polygons

The nested place polygon calculation
([explained in this post](https://blog.rustprooflabs.com/2021/01/pgosm-flex-improved-openstreetmap-places-postgis))
adds minimal overhead to smaller regions, e.g. Colorado with a 225 MB PBF input file.
Larger regions, such as North America (12 GB PBF),
are impacted more severely as a difference in processing time.
Calculating nested place polygons for Colorado adds less than 30 seconds on an 8 minute process,
taking about 5% longer.
A larger region, such as North America, can take 33% longer adding more than
an hour and a half to the total processing time.
See the [performance section](performance.md) for more details.


Use `--skip-nested` to bypass the calculation of nested admin polygons.


## Use `--pg-dump` to export data

> The `--pg-dump` option was added in 0.7.0.  Prior versions defaulted to using `pg_dump` and provided a `--skip-dump` option to override.  The default now is to only use `pg_dump` when requested.  See [#266](https://github.com/rustprooflabs/pgosm-flex/issues/266) for more.


A `.sql` file can be created using `pg_dump` as part of the processing
for easy loading into one or more external Postgres databases.
Add `--pg-dump` to the `docker exec` command to enable this feature.

The following example
creates an empty `myosm` database to load the processed and dumped OpenStreetMap
data.


```bash
psql -d postgres -c "CREATE DATABASE myosm;"
psql -d myosm -c "CREATE EXTENSION postgis;"

psql -d myosm \
    -f ~/pgosm-data/pgosm-flex-north-america-us-district-of-columbia-default-2023-01-21.sql
```

> The above assumes a database user with `superuser` permissions is used. See the [Postgres Permissions](postgres-permissions.md) section for a more granular approach to permissions.





## Use `--help`

The PgOSM Docker image can provide command line help.
The Python script that controls PgOSM Flex's behavior is built using the
`click` module, providing built-in `--help`.
Use `docker exec` to show the full help.


```bash
docker exec -it pgosm python3 docker/pgosm_flex.py --help
```

The first portion of the `--help` output is shown here.

```bash
Usage: pgosm_flex.py [OPTIONS]

  Run PgOSM Flex within Docker to automate osm2pgsql flex processing.

Options:
  --ram FLOAT               Amount of RAM in GB available on the machine
                            running the Docker container. This is used to
                            determine the appropriate osm2pgsql command via
                            osm2pgsql-tuner recommendation engine.  [required]
  --region TEXT             Region name matching the filename for data sourced
                            from Geofabrik. e.g. north-america/us. Optional
                            when --input-file is specified, otherwise
                            required.
  --subregion TEXT          Sub-region name matching the filename for data
                            sourced from Geofabrik. e.g. district-of-columbia
  --data-only               When set, skips running Sqitch and importing QGIS
                            Styles.

```






