# Layersets


A layerset in PgOSM Flex defines one or more layers, where each layer
includes one or more [tables](layersets.md#tables).  For example, the
`minimal` layerset (see [flex-config/layerset/minimal.ini](https://github.com/rustprooflabs/pgosm-flex/blob/main/flex-config/layerset/minimal.ini))
is defined as shown in the following snippet.


```ini
[layerset]
place=true
poi=true
road_major=true
```


In the above example, `place`, `poi` and `road_major` are the included
Layers.  This results in nine (9) total tables being loaded.
There is the standard
[meta table `osm.pgosm_flex`](quick-start.md#meta-table), plus eight (8)
tables for the three (3) layers.  The place layer has four tables,
poi has three (3) and road major has one (1). 


    ┌────────┬──────────────────────┬───────┬───────────────────┐
    │ s_name │        t_name        │ rows  │ size_plus_indexes │
    ╞════════╪══════════════════════╪═══════╪═══════════════════╡
    │ osm    │ pgosm_flex           │     1 │ 32 kB             │
    │ osm    │ place_line           │   128 │ 168 kB            │
    │ osm    │ place_point          │   124 │ 128 kB            │
    │ osm    │ place_polygon        │   217 │ 496 kB            │
    │ osm    │ place_polygon_nested │    22 │ 304 kB            │
    │ osm    │ poi_line             │   255 │ 128 kB            │
    │ osm    │ poi_point            │ 10876 │ 2360 kB           │
    │ osm    │ poi_polygon          │ 12413 │ 6456 kB           │
    │ osm    │ road_major           │  8097 │ 2504 kB           │
    └────────┴──────────────────────┴───────┴───────────────────┘


## Included layersets

PgOSM Flex includes a few layersets to get started as examples.
These layersets are defined under `flex-config/layerset/`.
If the `--layerset` is not defined, the `default` layerset is used.

* `basic`
* `default`
* `everything`
* `minimal`

Using a built-in layerset other than `default` is done by defining
the `--layerset` option.  The following example uses the `minimal` layerset
shown above.


```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --layerset=minimal \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```

The output from running PgOSM Flex indicates which layers are being loaded.

```
2023-01-29 08:47:12,191:INFO:pgosm-flex:helpers:Including place
2023-01-29 08:47:12,192:INFO:pgosm-flex:helpers:Including poi
2023-01-29 08:47:12,192:INFO:pgosm-flex:helpers:Including road_major
```



## Custom layerset


A layerset including the `poi` and `road_major` layers would look
like:

```ini
[layerset]
poi=true
road_major=true
```


To use the `--layerset-path` option for custom layerset
definitions, link the directory containing custom styles
to the Docker container in the `docker run` command.
If the `custom-layerset` directory is in the home (`~`) directory, adding
`-v ~/custom-layerset:/custom-layerset \` to the `docker run`
command will make the layerset definition available to the Docker container.
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
(`--layerset-path`) to the `docker exec` command.
The value provided to `--layerset-path` must match the path linked in the
`docker exec` command.


```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --layerset=poi \
    --layerset-path=/custom-layerset/ \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```

## Excluding layers

To exclude layers from a layerset they can be simply omitted from the
`.ini` file.  They can also be set explicitly to `false`
such as `road_major=false`.


# Layers

This section documents the layers created by PgOSM Flex. The
[layerset](layersets.md) defined at runtime (to `docker exec`)
determines which tables are loaded, based on `layer_group`.

The `amenity` layer has each of the three types of geometry
commonly associated, so has three tables:

* `osm.amenity_line`
* `osm.amenity_point`
* `osm.amenity_polygon`

The definitive answer to "what is in a layer" is defined by the
associated Lua code under `flex-config/style/<layer group>.lua`

## Layer definitions

The layers are determined by the `.lua` files available
in the [`flex-config/style`](https://github.com/rustprooflabs/pgosm-flex/tree/main/flex-config/style)
directory.  Each `.lua` file in the `style` folder has a matching `.sql`
file in the [`flex-config/sql`](https://github.com/rustprooflabs/pgosm-flex/tree/main/flex-config/sql)
directory. For example,
the road layer is defined by `flex-config/style/road.lua` and
`flex-config/sql/road.sql`, and creates three (3) tables ([see Tables section](layersets.md#tables)).



## Tables

Using `--layerset=everything` creates 45 tables and one (1)
materialized view.  The following table lists the groups of
tables created with the types of layer it is.


| Layer | Geometry Types |
|-------------|-------------|
| amenity | line, point, polygon |
| building | point, polygon, combined |
| indoor | line, point, polygon |
| infrastructure | line, point, polygon |
| landuse | point, polygon |
| leisure | point, polygon |
| natural | line, point, polygon |
| place | line, point, polygon, *polygon_nested* |
| poi | line, point, polygon, combined  |
| public_transport | line, point, polygon |
| road | line, point, polygon |
| road_major | line (*table name is non-standard, `osm.road_major`*) |
| shop | point, polygon, combined |
| tags | *Provides full JSONB tags* |
| traffic | line, point, polygon |
| unitable | *generic `geometry`* |
| water | line, point, polygon |



## Inclusion by OpenStreetMap tags

Data is included in layers based on the tags from OpenStreetMap.


### Amenity


OpenStreetMap tags included:

* amenity
* bench
* brewery


### Building


OpenStreetMap tags included:

* building
* building:part
* door
* office

Plus: Address only locations.

See [issue #97](https://github.com/rustprooflabs/pgosm-flex/issues/97)
for more details about Address only locations.


### Indoor

OpenStreetMap tags included:

* indoor
* door
* entrance

### Infrastructure

OpenStreetMap tags included:

* aeroway
* amenity
* emergency
* highway
* man_made
* power
* utility



### Landuse

OpenStreetMap tags included:

* landuse


### Leisure

OpenStreetMap tags included:

* leisure


### Natural

OpenStreetMap tags included:

* natural

Excludes water/waterway values.  See [Water section](#water).


### Place

OpenStreetMap tags included:

* admin_level
* boundary
* place


### POI (Points of Interest)

The POI layer overlaps many of the other existing layers, though with
slightly different definitions.  e.g. only buildings with either a
name and/or operator are included.

OpenStreetMap tags included:

* building
* shop
* amenity
* leisure
* man_made
* tourism
* landuse
* natural
* historic


### Public Transport

OpenStreetMap tags included:

* public_transport
* aerialway
* railway

Additional important tags considered, but not used for primary selection:

* bus
* railway
* lightrail
* train
* highway


### Road

OpenStreetMap tags included:

* highway

Additional important tags considered, but not used for primary selection:

* maxspeed
* layer
* tunnel
* bridge
* access
* oneway


### Shop

OpenStreetMap tags included:

* shop
* amenity



### Tags

The `osm.tags` table stores all tags for all items loaded.


### Traffic

OpenStreetMap tags included:

* highway
* railway
* barrier
* traffic_calming
* amenity
* noexit



### Unitable

All data is stuffed into a generic `GEOMETRY` column.


### Water

OpenStreetMap tags included:

* natural
* waterway

Uses specific `natural` types, attempts to avoid overlap
with the Natural layer. See the [Natural section](#natural).



## Views

The need for views is diminishing as PgOSM Flex matures along with
osm2pgsql's Flex output.

The materialized view that will likely remain is:

* `osm.vplace_polygon_subdivide`

The other views currently created in PgOSM Flex 0.8.x will
be removed in v0.9.0, see [issue #320](https://github.com/rustprooflabs/pgosm-flex/issues/320).


* `osm.vbuilding_all`
* `osm.vpoi_all`
* `osm.vshop_all`


