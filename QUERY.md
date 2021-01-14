# Querying with PgOSM-Flex


## Places

Use the `osm.vplace_polygon` view for most uses.  When a relation exists along with multiple polygon
parts, the view removes the non-relation polygons and only keeps the relation.

[Commerce City, Colorado, relation 112806](https://www.openstreetmap.org/relation/112806)
has 84 members as of 1/13/2021.  The view only returns one row when searching by name.

```sql
SELECT COUNT(*)
    FROM osm.vplace_polygon
    WHERE name = 'Commerce City'
;
```

```bash
count|
-----|
    1|
```


When querying the base table by name, 52 rows are returned.

```sql
SELECT COUNT(*)
    FROM osm.place_polygon
    WHERE name = 'Commerce City'
;
```



```bash
count|
-----|
   52|
```


> Note: The count here is different than in OpenStreetMap.org because this is only looking at polygons.  The OpenStreetMap.org view also includes nodes and lines where this query does not.

