# Routing Data and Process

This page describes some of the processes involved in the routing edge network.

## Length Based Costs

The `osm.routing_prepare_road_network` procedure generates accurate `cost_length`
by casting data to `GEOGRAPHY` and generates `cost_length_forward`
and `cost_length_reverse` to natively support directionally-enforced routing
without additional steps.

This procedure was created as part of the migration to pgRouting 4.0, see
[#408](https://github.com/rustprooflabs/pgosm-flex/pull/408) for notes about
the initial migration.

> ⚠️ The routing procedures began to be added in PgOSM Flex 1.1.2 and continue to evolve.
> These procedures should be treated as a new feature with potential bugs lurking.



## Costs Including One Way Restrictions

Most real-world routing examples need to be aware of one-way travel restrictions.
The `oneway` column in PgOSM Flex's road tables (e.g. `osm.road_line`) uses
[osm2pgsql's `direction` data type](https://osm2pgsql.org/doc/manual.html#type-conversions). 
This direction data type resolves to `int2` in Postgres. Valid values are:

* `0`: Not one way
* `1`: One way, forward travel allowed
* `-1`: One way, reverse travel allowed
* `NULL`: It's complicated. See [#172](https://github.com/rustprooflabs/pgosm-flex/issues/172).


Forward and reverse cost columns are calculated in the `cost_length_forward`
and `cost_length_reverse` columns within the `osm.routing_prepare_road_network()` procedure.


## Travel Time Costs

With lengths and one-way already calculated per edge, speed limits can be used
to compute travel time costs. The `osm.routing_prepare_road_network` procedure
calculate travel times in seconds into two `motor` travel focused columns.
The `osm.route_motor_travel_time()` function uses these costs to compute travel times.

* `cost_motor_forward_s`
* `cost_motor_reverse_s`


The calculations use two sources of `maxspeed` to drive this logic.
The first source is the `maxspeed` value from each road segment from OpenStreetMap.
When that value is not set, the `maxspeed` value is used from the `pgosm.road`
lookup table based on `osm_type` (e.g. 'primary', 'residential')
packaged with PgOSM Flex. 

The `maxspeed` is multipled by `traffic_penalty_normal` to calculate a more realistic
travel time. The `traffic_penalty_normal` values can be between `0.0` (block routing entirely)
to `1.0` (no penalty). These values are pre-set in the `pgosm.road` table and can
be adjusted **before** running the `osm.routing_prepare_road_network` procedure
to use your adjusted values.


In most common routing scenarios this will under-report travel times due
to not considering for traffic signals, slowing down for corners, and traffic in
general.

