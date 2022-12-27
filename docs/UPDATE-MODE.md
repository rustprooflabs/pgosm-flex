# PgOSM Flex Update Mode

Running in experimental Update mode enables using osm2pgsql's `--append`
option.  Not to be confused with the `--append` option in PgOSM Flex prior to 0.7.0...


## Testing steps

Important -- Needs higher max connections!



```bash
docker stop pgosm && docker build -t rustprooflabs/pgosm-flex .
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex \
    -c max_connections=300
```

Run fresh import w/ D.C. using `--update create`. This ensures osm2pgsql
uses `--slim` w/out `--drop`.  Tested from commit `672d9fd`.


```bash
time docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --skip-nested --skip-dump \
    --update create

...

2022-12-27 09:02:37,654:INFO:pgosm-flex:helpers:PgOSM-Flex version:	0.6.3	672d9fd

...

real	0m43.904s
user	0m0.020s
sys	0m0.012s
```

Run with a second sub-region using `--update append`.

```bash
time docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=new-hampshire \
    --skip-nested --skip-dump \
    --update append

...

2022-12-27 10:14:26,792:INFO:pgosm-flex:helpers:2022-12-27 10:14:26  osm2pgsql took 1420s (23m 40s) overall.
2022-12-27 10:14:26,832:INFO:pgosm-flex:pgosm_flex:osm2pgsql completed
2022-12-27 10:14:26,832:INFO:pgosm-flex:pgosm_flex:Running with --update append: Skipping post-processing SQL
2022-12-27 10:14:26,832:INFO:pgosm-flex:pgosm_flex:Skipping pg_dump
2022-12-27 10:14:26,832:INFO:pgosm-flex:pgosm_flex:PgOSM Flex complete!

real	23m47.564s
user	0m0.083s
sys	0m0.025s

```

It seems to work, new output at the end: `Skipping post-processing SQL`.

Verified that both New Hampshire and D.C. regions were loaded in `osm.place_polygon`.


