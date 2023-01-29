# PgOSM Flex layersets


A layerset defines one or more layers, where each layer includes
one or more tables and/or views.
Layers are defined by a matched pair of Lua and SQL scripts.  For example,
the road layer is defined by `flex-config/style/road.lua` and
`flex-config/sql/road.sql`.


Layersets are defined in `.ini` files.


## Included layersets

PgOSM Flex includes a few layersets.  These are defined under `flex-config/layerset/`.
If the `--layerset` is not defined, the `default` layerset is used.

* `basic`
* `default`
* `everything`
* `minimal`

Using a built-in layerset other than `default` is done with
wih the `--layerset` option. 


```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --layerset=minimal \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```


## Custom layerset


A layerset including the `poi` and `road_major` layers would look
like:

```ini
[layerset]
poi=true
road_major=true
```

Layers not listed in the layerset `.ini` are not included.




## Using custom layersets

To use the `--layerset-path` option for custom layerset
definitions, link the directory containing custom styles
to the Docker container in the `docker run` command.
The custom styles will be available inside the container under
`/custom-layerset`.


```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -v ~/custom-layerset:/custom-layerset \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```

Define the layerset name (`--layerset=poi`) and path
(`--layerset-path`) to the `docker exec`.


```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --layerset=poi \
    --layerset-path=/custom-layerset/ \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```


