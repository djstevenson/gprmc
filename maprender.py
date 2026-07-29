#!/usr/bin/env python3

import mapnik

MIN_LON = -1.910
MIN_LAT = 50.720
MAX_LON = -1.35
MAX_LAT = 51.71

wgs84 = mapnik.Projection("EPSG:4326")
bng = mapnik.Projection("EPSG:27700")
transform = mapnik.ProjTransform(wgs84, bng)

bbox_wgs84 = mapnik.Box2d(
    MIN_LON,
    MIN_LAT,
    MAX_LON,
    MAX_LAT
)
bbox_bng = transform.forward(bbox_wgs84)

METRES_PER_PIXEL = 5

map_width_metres  = bbox_bng.maxx - bbox_bng.minx
map_height_metres = bbox_bng.maxy - bbox_bng.miny

WIDTH  = round(map_width_metres  / METRES_PER_PIXEL)
HEIGHT = round(map_height_metres / METRES_PER_PIXEL)

print(f"Map area: {map_width_metres / 1000:.1f} × "
      f"{map_height_metres / 1000:.1f} km")

print(f"Image: {WIDTH} × {HEIGHT} pixels")

m = mapnik.Map(WIDTH, HEIGHT)

mapnik.load_map(m, "map.xml")
m.zoom_to_box(bbox_bng)
mapnik.render_to_file(m, "route-map.png")
