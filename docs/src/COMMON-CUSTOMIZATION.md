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
checksum validation.

The `--region` option is still required, the `--subregion` option can be used
if desired.


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






