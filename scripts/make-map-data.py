#!/usr/bin/env python3
"""Builds the map data bundled with Paper & Grain from Natural Earth (public domain).

  scripts/make-map-data.py                 download the pinned Natural Earth files and write
                                           Resources/MapData/world.mapdata
  scripts/make-map-data.py --source DIR    read the same GeoJSON files from DIR instead of downloading
  scripts/make-map-data.py --fixture OUT   write a tiny synthetic test file (no download) to OUT

Downloading contacts GitHub (raw.githubusercontent.com); run it only when you mean to. The source is
pinned to a release tag, so the output can be reproduced. See Resources/MapData/CREDITS.md.

Output: a raw DEFLATE stream (zlib wbits -15, read by Foundation's `.zlib` decompression) of

  "PGMAP" u8 version=1
  land:    u32 ring count, rings
  lakes:   u32 ring count, rings
  borders: u32 line count, each: u8 flags (1 = disputed or not agreed), points
  places:  u32 count, each: i32 lon, i32 lat (1e-4 degree), u32 population,
           string name, string Italian name, string English name (u16 length + UTF-8)

A ring or line is u32 n, the first point as i32 lon, i32 lat (1e-4 degree), then n-1 deltas as
zig-zag varints. All integers are little endian.
"""
import argparse
import gzip
import io
import json
import struct
import sys
import urllib.request
import zlib
from pathlib import Path

TAG = "v5.1.2"
BASE = f"https://raw.githubusercontent.com/nvkelso/natural-earth-vector/{TAG}/geojson/"
FILES = {
    "land": "ne_50m_land.geojson",
    "borders": "ne_50m_admin_0_boundary_lines_land.geojson",
    "lakes": "ne_50m_lakes.geojson",
    "places": "ne_10m_populated_places.geojson",
}
SCALE = 10_000
# Boundary classes drawn dashed: anything the data does not mark as an agreed international boundary.
DASHED = ("disputed", "indefinite", "line of control", "breakaway", "claim", "lease", "overlay")


def zigzag(value):
    return (value << 1) ^ (value >> 63)


def varint(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def quantize(point):
    return round(point[0] * SCALE), round(point[1] * SCALE)


def simplify(points, tolerance):
    """Douglas-Peucker on quantized points, keeping the ends."""
    if len(points) < 3 or tolerance <= 0:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        ax, ay = points[first]
        bx, by = points[last]
        dx, dy = bx - ax, by - ay
        length = (dx * dx + dy * dy) ** 0.5
        best, index = -1.0, None
        for i in range(first + 1, last):
            px, py = points[i]
            if length == 0:
                distance = ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
            else:
                distance = abs(dy * px - dx * py + bx * ay - by * ax) / length
            if distance > best:
                best, index = distance, i
        if index is not None and best > tolerance:
            keep[index] = True
            stack.append((first, index))
            stack.append((index, last))
    return [p for p, k in zip(points, keep) if k]


def encode_line(points):
    out = bytearray(struct.pack("<I", len(points)))
    if not points:
        return bytes(out)
    out += struct.pack("<ii", *points[0])
    previous = points[0]
    for point in points[1:]:
        out += varint(zigzag(point[0] - previous[0]))
        out += varint(zigzag(point[1] - previous[1]))
        previous = point
    return bytes(out)


def string(value):
    data = (value or "").encode("utf-8")[:65535]
    return struct.pack("<H", len(data)) + data


def rings(geometry):
    kind = geometry["type"]
    if kind == "Polygon":
        return geometry["coordinates"]
    if kind == "MultiPolygon":
        return [ring for polygon in geometry["coordinates"] for ring in polygon]
    return []


def lines(geometry):
    kind = geometry["type"]
    if kind == "LineString":
        return [geometry["coordinates"]]
    if kind == "MultiLineString":
        return geometry["coordinates"]
    return []


def clean(points, tolerance, minimum):
    quantized = []
    for point in points:
        q = quantize(point)
        if not quantized or q != quantized[-1]:
            quantized.append(q)
    quantized = simplify(quantized, tolerance)
    return quantized if len(quantized) >= minimum else None


def build(sources, tolerance=60):
    """`sources` maps a theme to parsed GeoJSON. Tolerance is in 1e-4 degree (60 = about 0.7 km)."""
    out = bytearray(b"PGMAP" + bytes([1]))
    for theme in ("land", "lakes"):
        encoded = []
        for feature in sources[theme]["features"]:
            for ring in rings(feature["geometry"]):
                points = clean(ring, tolerance, 4)
                if points:
                    encoded.append(encode_line(points))
        out += struct.pack("<I", len(encoded)) + b"".join(encoded)
    encoded = []
    for feature in sources["borders"]["features"]:
        kind = str(feature["properties"].get("FEATURECLA") or feature["properties"].get("featurecla") or "").lower()
        flags = 1 if any(word in kind for word in DASHED) else 0
        for line in lines(feature["geometry"]):
            points = clean(line, tolerance, 2)
            if points:
                encoded.append(bytes([flags]) + encode_line(points))
    out += struct.pack("<I", len(encoded)) + b"".join(encoded)
    places = []
    for feature in sources["places"]["features"]:
        p = feature["properties"]
        lon, lat = feature["geometry"]["coordinates"][:2]
        name = p.get("NAME") or p.get("name") or ""
        if not name:
            continue
        population = int(p.get("POP_MAX") or p.get("pop_max") or 0)
        places.append(struct.pack("<iiI", round(lon * SCALE), round(lat * SCALE), max(0, population))
                      + string(name) + string(p.get("NAME_IT")) + string(p.get("NAME_EN")))
    out += struct.pack("<I", len(places)) + b"".join(places)
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    return compressor.compress(bytes(out)) + compressor.flush()


def fixture():
    """Synthetic shapes near southern Africa for unit tests. Not geography: every name says TEST."""
    def square(x0, y0, x1, y1):
        return {"type": "Polygon", "coordinates": [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]]}
    land = {"features": [
        {"geometry": {"type": "Polygon", "coordinates": [[[11.7, -17.0], [25.3, -17.0], [25.3, -22.0], [20.0, -22.0],
                                                           [20.0, -28.9], [16.5, -28.6], [11.7, -17.0]]]}},
        {"geometry": square(170.0, -45.0, 179.9, -35.0)},
        {"geometry": square(-179.9, -20.0, -175.0, -15.0)},
    ]}
    lakes = {"features": [{"geometry": square(15.5, -19.0, 16.5, -18.5)}]}
    borders = {"features": [
        {"properties": {"FEATURECLA": "International boundary (verify)"},
         "geometry": {"type": "LineString", "coordinates": [[20.0, -22.0], [20.0, -24.0]]}},
        {"properties": {"FEATURECLA": "Disputed (please verify)"},
         "geometry": {"type": "LineString", "coordinates": [[20.0, -24.0], [20.0, -28.9]]}},
    ]}
    places = {"features": [
        {"properties": {"NAME": "TEST Capital", "NAME_IT": "TEST Capitale", "NAME_EN": "TEST Capital", "POP_MAX": 400000},
         "geometry": {"coordinates": [17.08, -22.57]}},
        {"properties": {"NAME": "TEST Coast", "NAME_IT": "TEST Costa", "NAME_EN": "TEST Coast", "POP_MAX": 60000},
         "geometry": {"coordinates": [14.52, -22.95]}},
        {"properties": {"NAME": "TEST North", "NAME_IT": "", "NAME_EN": "", "POP_MAX": 30000},
         "geometry": {"coordinates": [15.95, -17.78]}},
        {"properties": {"NAME": "TEST Island", "NAME_IT": "TEST Isola", "NAME_EN": "TEST Island", "POP_MAX": 5000},
         "geometry": {"coordinates": [179.0, -40.0]}},
    ]}
    return build({"land": land, "lakes": lakes, "borders": borders, "places": places}, tolerance=0)


def download(name):
    url = BASE + name
    print("Downloading", url, file=sys.stderr)
    request = urllib.request.Request(url, headers={"User-Agent": "make-map-data"})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.GzipFile(fileobj=io.BytesIO(data)).read()
    return json.loads(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, help="read the GeoJSON files from this folder")
    parser.add_argument("--fixture", type=Path, help="write the synthetic test file here and stop")
    parser.add_argument("--output", type=Path, default=Path("Resources/MapData/world.mapdata"))
    args = parser.parse_args()
    if args.fixture:
        args.fixture.parent.mkdir(parents=True, exist_ok=True)
        args.fixture.write_bytes(fixture())
        print(args.fixture, args.fixture.stat().st_size, "bytes")
        return
    sources = {}
    for theme, name in FILES.items():
        sources[theme] = json.loads((args.source / name).read_text()) if args.source else download(name)
    data = build(sources)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(args.output, len(data), "bytes")


if __name__ == "__main__":
    main()
