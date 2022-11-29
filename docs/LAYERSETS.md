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


## Custom layerset


A layerset including the `poi` and `road_major` layers would look
like:

```ini
[layerset]
poi=true
road_major=true
```

Layers not listed in the layerset `.ini` are not included.

