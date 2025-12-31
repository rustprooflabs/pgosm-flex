# Routing with pgRouting 4

> If you are using a pgRouting prior to 4.0 see [Routing with pgRouting 3](./routing-3.md).

Create the `pgRouting` extension.

```sql
CREATE EXTENSION IF NOT EXISTS pgrouting;
```


# Process the OpenStreetMap Roads

For routing on `osm.road_line` data use the `osm.routing_prepare_road_network`
procedure to prepare the edge and vertex data used for routing.

```sql
CALL osm.routing_prepare_road_network();
```

The `osm.routing_prepare_road_network` procedure focuses on the most common use
cases of routing with the `osm.road_line` layer. It generates the edge/vertex
network for all data in the `osm.road_line` table. It generates accurate `cost_length`
by casting data to `GEOGRAPHY` and generates `cost_length_forward`
and `cost_length_reverse` to natively support directionally-enforced routing
without additional steps.


> ⚠️ The `osm.routing_prepare_road_network` procedure was added in PgOSM Flex 1.1.2
> and is a significant deviation in routing preparation along with pgRouting 4.0.
> This procedure should be treated as a new feature with potential bugs lurking.

This procedure was created as part of the migration to pgRouting 4.0, see
[#408](https://github.com/rustprooflabs/pgosm-flex/pull/408) for notes about
this.


## Timing for data preparation

This section outlines a few timing references to help gauge how long this might
take for your region's data. Note these are generic timings using the built-in
database in the PgOSM Flex Docker image, without any tuning from default
configuration. Your tuning and your hardware will influence these timings.

* D.C.: 18 seconds
* Colorado: 11.5 minutes

The Colorado data set has  1.2M input roads resulting in 2.6M edges after splitting.

```
┌────────┬───────────────────┬─────────┐
│ s_name │      t_name       │  rows   │
╞════════╪═══════════════════╪═════════╡
│ osm    │ routing_road_edge │ 2560998 │
│ osm    │ road_line         │ 1189678 │
└────────┴───────────────────┴─────────┘
```


# Costs for Routing

Routing uses a concept of cost to determine the best route to traverse. Cost can
be defined in a variety of methods. This section explores a few options.

* `cost_length`
* `cost_length_forward`
* `cost_length_reverse`



The procedure automatically generates a `cost_length` column using `GEOGRAPHY`
for accurate calculations in meters.

The forward/reverse costs start with `cost_length` calculation and apply the
OpenStreetMap `oneway` restrictions.


## Costs Including One Way Restrictions

Many real-world routing examples need to be aware of one-way travel restrictions.
The `oneway` column in PgOSM Flex's road tables uses
[osm2pgsql's `direction` data type](https://osm2pgsql.org/doc/manual.html#type-conversions). 
This direction data type resolves to `int2` in Postgres. Valid values are:

* `0`: Not one way
* `1`: One way, forward travel allowed
* `-1`: One way, reverse travel allowed
* `NULL`: It's complicated. See [#172](https://github.com/rustprooflabs/pgosm-flex/issues/172).

> Forward and reverse cost columns are calculated in the `cost_length_forward`
> and `cost_length_reverse` columns within the `osm.routing_prepare_road_network()` procedure.


## Travel Time Costs

With lengths and one-way already calculated per edge, speed limits can be used
to compute travel time costs.

The `maxspeed` data in `pgosm.road` can be used to generate travel time costs
per segment.
[Chapter 16 of Mastering PostGIS and OpenStreetMap](https://book.postgis-osm.com/ch_pgrouting/improve-specific-routing.html) (paid content) provides examples of this approach.


# Determine route start and end

The following query identifies the vertex IDs for a start and end point 
to use for later queries. The query uses an input set of points
created from specific longitude/latitude values.
Use the `start_id` and `end_id` values from this query
in subsequent queries through the `:start_id` and `:end_id` variables
via DBeaver.

> This query simulates a GUI allowing user to click on start/end points on a map,
> resulting in longitude and latitude values.


```sql
WITH s_point AS (
SELECT v.id AS start_id, v.geom
    FROM osm.routing_road_vertex v
    INNER JOIN (SELECT
        ST_Transform(ST_SetSRID(ST_MakePoint(-77.0211, 38.92255), 4326), 3857)
            AS geom
        ) p ON v.geom <-> p.geom < 20
    ORDER BY v.geom <-> p.geom
    LIMIT 1
), e_point AS (
SELECT v.id AS end_id, v.geom
    FROM osm.routing_road_vertex v
    INNER JOIN (SELECT
        ST_Transform(ST_SetSRID(ST_MakePoint(-77.0183, 38.9227), 4326), 3857)
            AS geom
        ) p ON v.geom <-> p.geom < 20
    ORDER BY v.geom <-> p.geom
    LIMIT 1
)
SELECT s_point.start_id, e_point.end_id
        , s_point.geom AS geom_start
        , e_point.geom AS geom_end
    FROM s_point, e_point
;
```

```bash
┌──────────┬────────┐
│ start_id │ end_id │
╞══════════╪════════╡
│    14630 │  14686 │
└──────────┴────────┘
```


> Warning: The vertex IDs returned by the above query will vary. The pgRouting functions that generate this data do not guarantee data will always be generated in precisely the same order, causing these IDs to be different.


The vertex IDs returned were `14630` and `14686`.  These points
span a particular segment of road (`osm_id = 6062791`) that is tagged
as `highway=residential` and `access=private`.
This segment is used to illustrate how the calculated access
control columns, `route_motor`, `route_cycle` and `route_foot`,
can influence route selection.



```sql
SELECT *
    FROM routing.road_line
    WHERE osm_id = 6062791
;
```

![Screenshot from QGIS showing two labeled points, 14630 and 14686. The road between the two points is shown with a light gray dash indicating the access tag indicates non-public travel.](dc-example-route-start-end-vertices.png)

> See `flex-config/helpers.lua` functions (e.g. `routable_motor()`) for logic behind access control columns.



# Route!


Using `pgr_dijkstra()` and no additional filters will
use all roads from OpenStreetMap without regard to mode of travel
or access rules.
This query picks a route that traverses sidewalks and
a section of road with the
[`access=private` tag from OpenStreetMap](https://wiki.openstreetmap.org/wiki/Tag:access%3Dprivate).
The key details to focus on in the following queries
is the string containing a SQL query passed into the `pgr_dijkstra()`
function.  This first example is a simple query from the
`osm.routing_road_edge` table.

> Note:  These queries are intended to be ran using DBeaver.  The `:start_id` and `:end_id` variables work within DBeaver, but not via `psql` or QGIS.  Support in other GUIs is unknown at this time (PRs welcome!).


```sql
SELECT d.*, n.geom AS node_geom, e.geom AS edge_geom
    FROM pgr_dijkstra(
        'SELECT e.edge_id AS id
                , e.vertex_id_source AS source
                , e.vertex_id_target AS target
                , e.cost_length AS cost
                , e.geom
            FROM osm.routing_road_edge e
            ',
            :start_id, :end_id, directed := False
        ) d
    INNER JOIN osm.routing_road_vertex n ON d.node = n.id
    LEFT JOIN osm.routing_road_edge e ON d.edge = e.edge_id
;
```


![Screenshot from DBeaver showing the route generated with all roads and no access control. The route is direct, traversing the road marked access=private.](dc-example-route-start-no-access-control.png)




# Route motorized

The following query modifies the query passed in to `pgr_dijkstra()`
to join the `osm.routing_road_edge` table to the
`routing.road_line` table.  This allows using attributes available
in the upstream table for additional routing logic.
The join clause includes a filter on the `route_motor` column.

From the comment on the `osm.road_line.route_motor` column:

> "Best guess if the segment is route-able for motorized traffic. If access is no or private, set to false. WARNING: This does not indicate that this method of travel is safe OR allowed!"

Based on this comment, we can expect that adding `AND route_motor`
into the filter will ensure the road type is suitable for motorized
traffic, and it excludes routes marked private. 


```sql
SELECT d.*, n.geom AS node_geom, e.geom AS edge_geom
    FROM pgr_dijkstra(
        'SELECT e.edge_id AS id
                , e.vertex_id_source AS source
                , e.vertex_id_target AS target
                , e.cost_length AS cost,
                e.geom
            FROM osm.routing_road_edge e
            WHERE e.route_motor
            ',
            :start_id, :end_id, directed := False
        ) d
    INNER JOIN osm.routing_road_vertex n ON d.node = n.id
    LEFT JOIN osm.routing_road_edge e ON d.edge = e.edge_id
;
```


![Screenshot from DBeaver showing the route generated with all roads and limiting based on route_motor. The route bypasses the road(s) marked access=no and access=private.](dc-example-route-start-motor-access-control.png)

# One-way Aware Routing

The route shown in the previous example now respects the
access control and limits to routes suitable for motorized traffic.
It, however, **did not** respect the one-way access control.
The very first segment (top-left corner of screenshot) went
the wrong way on a one-way street.
This behavior is a result of the simple length-based cost model.


This query uses the new reverse cost column, and changes
`directed` from `False` to `True`.
If you do not see the route shown in the screenshot below, try switching the
`:start_id` and `:end_id` values.


```sql
SELECT d.*, n.geom AS node_geom, e.geom AS edge_geom
    FROM pgr_dijkstra(
        'SELECT e.edge_id AS id
                , e.vertex_id_source AS source
                , e.vertex_id_target AS target
                , e.cost_length_forward AS cost
                , e.cost_length_reverse AS reverse_cost
                , e.geom
            FROM osm.routing_road_edge e
            WHERE e.route_motor
            ',
            :start_id, :end_id, directed := True
        ) d
    INNER JOIN osm.routing_road_vertex n ON d.node = n.id
    LEFT JOIN osm.routing_road_edge e ON d.edge = e.edge_id
;
```

![Screenshot from DBeaver showing the route generated with all roads and limiting based on route_motor and using the improved cost model including forward and reverse costs. The route bypasses the road(s) marked access=no and access=private, as well as respects the one-way access controls.](dc-example-route-start-motor-access-control-oneway.png)


# Routing with Water

PgOSM Flex also includes a procedure to prepare a routing network using
the `osm.water_line` table.

```sql
CALL osm.routing_prepare_water_network();
```

Find the `vertex_id` for start and end nodes, similar to approach above
with roads.

```sql

WITH s_point AS (
SELECT v.id AS start_id, v.geom
    FROM osm.routing_water_vertex v
    INNER JOIN (SELECT
        ST_Transform(ST_SetSRID(ST_MakePoint(-77.050625, 38.908953), 4326), 3857)
            AS geom
        ) p ON v.geom <-> p.geom < 200
    ORDER BY v.geom <-> p.geom
    LIMIT 1
), e_point AS (
SELECT v.id AS end_id, v.geom
    FROM osm.routing_water_vertex v
    INNER JOIN (SELECT
        ST_Transform(ST_SetSRID(ST_MakePoint(-77.055645, 38.888747), 4326), 3857)
            AS geom
        ) p ON v.geom <-> p.geom < 200
    ORDER BY v.geom <-> p.geom
    LIMIT 1
)
SELECT s_point.start_id, e_point.end_id
        , s_point.geom AS geom_start
        , e_point.geom AS geom_end
    FROM s_point, e_point
;
```


Route, using the directional approach.

```sql
SELECT d.*, n.geom AS node_geom, e.geom AS edge_geom
    FROM pgr_dijkstra(
        'SELECT e.edge_id AS id
                , e.vertex_id_source AS source
                , e.vertex_id_target AS target
                , e.cost_length_forward AS cost
                , e.cost_length_reverse AS reverse_cost
                , e.geom
            FROM osm.routing_water_edge e
            ',
            :start_id, :end_id, directed := True
        ) d
    INNER JOIN osm.routing_water_vertex n ON d.node = n.id
    LEFT JOIN osm.routing_water_edge e ON d.edge = e.edge_id
;
```

![Example route using D.C. water layer.](dc-water-route-example.png)

## Challenge: Polygons with Water Routing

Waterway routing using lines only is often complicated by the nature of waterways
and the way routes flow through steams and rivers (lines) and also through ponds
and lakes (polygons). The data prepared by the above procedure only provides
the line-based functionality.

The following image ([source](https://blog.rustprooflabs.com/2022/10/pgrouting-lines-through-polygons))
visualizes the impact polygons can have on a line-only routing network for water routes.

![Image alternates between showing / hiding water polygons, creating significant gaps in the routing network.](https://blog.rustprooflabs.com/static/images/water-polygons-are-important-for-routing.gif)



See the [Routing with Lines through Polygons](https://blog.rustprooflabs.com/2022/10/pgrouting-lines-through-polygons)
blog post to explore one possible approach to solving this problem.

