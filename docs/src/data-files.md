# Data Files

PgOSM Fle will automatically manage downloads of the appropriate data and `.md5`
files from the [Geofabrik download server](https://download.geofabrik.de/).
When using the default behavior, PgOSM Flex will automatically start downloading
the two necessary files:

* `<region/subregion>-latest.osm.pbf`
* `<region/subregion>-latest.osm.pbf.md5`

The data path on the host machine is defined via the `docker run` command. This
documentation always uses `~/pgosm-data` per the [quick start](quick-start.md).

```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    ...
```

> See the [Selecting Region and Sub-region](common-customization.md#selecting-region-and-subregion)
> section for more about the default behavior.



There are two methods to override this default behavior: specify `--pgosm-date`
or use `--input-file`.
If you have manually saved files in the path used by PgOSM Flex using `-latest`
in the filename, they **will be overwritten** if you are not using one of the
methods described below.


## Specific date with `--pgosm-date`

Use `--pgosm-date` to specify a specific date for the data.  The date specified
must be in `yyyy-mm-dd` format.
This mode requires you have a valid `.pbf` and matching `.md5` file in order to
function. The following example shows the `docker exec` command along with
a `--pgosm-date` defined.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --pgosm-date=2024-05-14
```

The output from running should confirm it finds and uses the file with the
specified date.
Remember, the paths reported from Docker (`/app/output/`) report the
container-internal path, not your local path on the host.

```bash
INFO:pgosm-flex:geofabrik:PBF File exists /app/output/district-of-columbia-2024-05-14.osm.pbf
INFO:pgosm-flex:geofabrik:PBF & MD5 files exist.  Download not needed
INFO:pgosm-flex:geofabrik:Copying Archived files
INFO:pgosm-flex:pgosm_flex:Running osm2pgsql
```

If a date is specified without matching file(s) it will raise an error and exit.

```bash
ERROR:pgosm-flex:geofabrik:Missing PBF file for 2024-05-15. Cannot proceed.
```


## Specific input file with `--input-file`

The automatic Geofabrik download can be overridden by providing PgOSM Flex
with the path to a valid `.osm.pbf` file using `--input-file`.
This option overrides the default file handling, archiving, and MD5
checksum validation.  With `--input-file` you can use a custom `osm.pbf`
you created, or use it to simply remove the need for an internet connection
from the instance running the processing.

> Note: The `--region` option is always required, the `--subregion` option can be used with `--input-file` to put the information in the `subregion` column of `osm.pgosm_flex`.


### Small area / custom extract

Some of the smallest subregions provided by Geofabrik are quite large compared
to the area of interest for a project.
The `osmium` tool makes it quick and easy to
[extract a bounding box](https://docs.osmcode.org/osmium/latest/osmium-extract.html).
The following example extracts an area roughly around Denver, Colorado.
It takes about 3 seconds to extract the 3.2 MB `denver.osm.pbf` output from
the 239 MB input.

```bash
osmium extract --bbox=-105.0193,39.7663,-104.9687,39.7323 \
    -o denver.osm.pbf \
    colorado-2023-04-18.osm.pbf
```

The PgOSM Flex processing time for the smaller Denver region takes less than 20 seconds on a
typical laptop, versus 11 minutes for all of Colorado.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=custom \
    --subregion=denver \
    --input-file=denver.osm.pbf \
    --layerset=everything
```