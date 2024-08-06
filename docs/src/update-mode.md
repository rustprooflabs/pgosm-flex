# Using Update Mode

Running with `--update` enables using osm2pgsql's `--append` option to load a second
input file. The PgOSM Flex functionality uses `--update create` and `--update append`.
See the discussion in [#275](https://github.com/rustprooflabs/pgosm-flex/issues/275)
for more context behind the intent for this feature.

Using `--update append` requires the initial import used `--update create`. Attempting
to use `--update append` without first using `--update create` results in the error:
"ERROR: This database is not updatable. To create an updatable database use --slim (without --drop)."


If your goal is to easily refresh the data for a single, standard region/sub-region
you should investigate the [`--replication` feature](/replication.md). Using
replication is the easier and more efficient way to maintain data.


> Note: This is **not** the `--append` option that existed in PgOSM Flex 0.6.3 and prior.

## Example

The following command uses `--update create` to load the `district-of-columbia`
sub-region. This example assumes you have set the environment variables and
have ran the docker container as shown in the [Quick Start](quick-start.md) section.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --update create
```

The following loads a second sub-region (`maryland`) using `--update append`.

```bash
time docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=maryland \
    --update append
```



## Smaller test

> This section has notes that probably belong elsewhere but I'm leaving them here for now.
> They were initially helpful for testing the logic for this functionality.

Put the following into `~/pgosm-data/extracts/colorado-extract.json`.

```json
{
    "directory": "/home/ryanlambert/pgosm-data/",
    "extracts": [
        {
            "output": "colorado-boulder-latest.osm.pbf",
            "description": "Area extracted around Boulder, Colorado",
            "bbox": {
                "left": -105.30,
                "right": -105.20,
                "top": 40.07,
                "bottom": 39.98
            }
        },
        {
            "output": "colorado-longmont-latest.osm.pbf",
            "description": "Area extracted around Longmont, Colorado",
            "bbox": {
                "left": -105.15,
                "right": -105.05,
                "top": 40.21,
                "bottom": 40.12
            }
        }
    ]
}
```


Create Boulder and Longmont extracts using `osmium extract`.

```bash
osmium extract -c extracts/colorado-extracts.json colorado-2022-12-27.osm.pbf
```


```bash
ryanlambert@tag201:~/pgosm-data$ ls -alh | grep boulder
-rw-rw-r--  1 ryanlambert ryanlambert 2.4M Dec 27 14:31 colorado-boulder-latest.osm.pbf
ryanlambert@tag201:~/pgosm-data$ ls -alh | grep longmont
-rw-rw-r--  1 ryanlambert ryanlambert 988K Dec 27 14:31 colorado-longmont-latest.osm.pbf
```

Takes 11 seconds.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=colorado-longmont --input-file colorado-longmont-latest.osm.pbf \
    --update create
```

Takes 2 minutes.


```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=colorado-boulder --input-file colorado-boulder-latest.osm.pbf \
    --update append
```

