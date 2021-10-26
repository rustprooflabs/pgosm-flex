## PgOSM Flex layersets

A layerset defines one or more layers, where each layer includes
one or more tables and/or views.

Layersets are defined in `.ini` files. A few layersets are included with PgOSM Flex under
`flex-config/layerset/`.

A layerset including the `poi` and `road_major` layers would look
like:

```ini
[layerset]
poi=true
road_major=true
```

Layers not listed in the layerset `.ini` are not included.

