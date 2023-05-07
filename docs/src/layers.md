# Layers

This page documents the layers created by PgOSM Flex. The
[layerset](layersets.md) defined at runtime (to `docker exec`)
determines which tables are loaded, based on `layer_group`.

The `amenity` `layer_group` has each of the three types of geometry
commonly associated, so has three tables:

* `osm.amentiy_line`
* `osm.amentiy_point`
* `osm.amentiy_polygon`

The definitive answer to "what is in a layer" is defined by the
associated Lua code under `flex-config/style/<layer group>.lua`

## Tables

Using `--layerset=everything` creates 42 tables, 2 views, and 2 
materialized views.  The following table lists the groups of
tables created with the types of layer it is.


| Layer Group | Layer Types |
|-------------|-------------|
| amenity | line, point, polygon |
| building | point, polygon |
| indoor | line, point, polygon |
| infrastructure | line, point, polygon |
| landuse | point, polygon |
| leisure | point, polygon |
| natural | line, point, polygon |
| place | line, point, polygon, *polygon_nested* |
| poi | line, point, polygon  |
| public_transport | line, point, polygon |
| road | line, *major*, point, polygon |
| shop | point, polygon |
| tags | *Provides full JSONB tags* |
| traffic | line, point, polygon |
| unitable | *generic `geometry`* |
| water | line, point, polygon |

## Views

As PgOSM Flex matures (along with osm2pgsql's Flex output!) the
need for views is diminishing.  The materialized view that will likely
remain is:

* `osm.vplace_polygon_subdivide`



The other views currently created in PgOSM Flex 0.8.x will
be removed in v0.9.0, see [issue #320](https://github.com/rustprooflabs/pgosm-flex/issues/320).


* `osm.vbuilding_all`
* `osm.vpoi_all`
* `osm.vshop_all`



## Amenity


OpenStreetMap tags included:

* amenity
* bench
* brewery


## Building


OpenStreetMap tags included:

* building
* building:part
* door
* office

Plus: Address only locations.

See [issue #97](https://github.com/rustprooflabs/pgosm-flex/issues/97)
for more details about Address only locations.


## Indoor

OpenStreetMap tags included:

* indoor
* door
* entrance

## Infrastructure

OpenStreetMap tags included:

* aeroway
* amenity
* emergency
* highway
* man_made
* power
* utility



## Landuse

OpenStreetMap tags included:

* landuse


## Leisure

OpenStreetMap tags included:

* leisure


## Natural

OpenStreetMap tags included:

* natural

Excludes water/waterway values.  See [Water section](#water).


## Place

OpenStreetMap tags included:

* admin_level
* boundary
* place


## POI (Points of Interest)

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


## Public Transport

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


## Road

OpenStreetMap tags included:

* highway

Additional important tags considered, but not used for primary selection:

* maxspeed
* layer
* tunnel
* bridge
* access
* oneway


## Shop

OpenStreetMap tags included:

* shop
* amenity



## Tags

The `osm.tags` table stores all tags for all items loaded.


## Traffic

OpenStreetMap tags included:

* highway
* railway
* barrier
* traffic_calming
* amenity
* noexit



## Unitable

All data is stuffed into a generic `GEOMETRY` column.


## Water

OpenStreetMap tags included:

* natural
* waterway

Uses specific `natural` types, attempts to avoid overlap
with the Natural layer. See the [Natural section](#natural).


