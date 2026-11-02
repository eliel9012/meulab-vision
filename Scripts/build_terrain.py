#!/usr/bin/env python3
"""Build the Franca radar height field from public Mapzen Terrarium tiles.

Requires Pillow. Samples a 401×401 WGS84 terrain grid at 1 km ENU spacing.
The output is signed 16-bit, little-endian elevation in meters above sea level.
"""

import io
import json
import math
import struct
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Resources" / "FrancaTerrain.bin"
METADATA = ROOT / "Resources" / "FrancaTerrain.json"
LAT = -20.51
LON = -47.40
RADIUS_METERS = 200_000
SPACING_METERS = 1_000
WIDTH = 2 * RADIUS_METERS // SPACING_METERS + 1
ZOOM = 9
TILE_SIZE = 256
SOURCE = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium"


def ecef(lat: float, lon: float) -> tuple[float, float, float]:
    a = 6_378_137.0
    e2 = 1 - (1 - 1 / 298.257223563) ** 2
    phi, lam = math.radians(lat), math.radians(lon)
    n = a / math.sqrt(1 - e2 * math.sin(phi) ** 2)
    return (n * math.cos(phi) * math.cos(lam),
            n * math.cos(phi) * math.sin(lam),
            n * (1 - e2) * math.sin(phi))


ORIGIN = ecef(LAT, LON)
PHI, LAM = math.radians(LAT), math.radians(LON)
EAST = (-math.sin(LAM), math.cos(LAM), 0.0)
NORTH = (-math.sin(PHI) * math.cos(LAM),
         -math.sin(PHI) * math.sin(LAM), math.cos(PHI))
UP = (math.cos(PHI) * math.cos(LAM),
      math.cos(PHI) * math.sin(LAM), math.sin(PHI))


def coordinate(east: float, north: float) -> tuple[float, float]:
    """Intersect the receiver's ENU column with the WGS84 ellipsoid."""
    a2 = 6_378_137.0 ** 2
    b2 = (6_378_137.0 * (1 - 1 / 298.257223563)) ** 2
    q = [ORIGIN[i] + east * EAST[i] + north * NORTH[i] for i in range(3)]
    u = UP
    aa = (u[0] ** 2 + u[1] ** 2) / a2 + u[2] ** 2 / b2
    bb = 2 * ((q[0] * u[0] + q[1] * u[1]) / a2 + q[2] * u[2] / b2)
    cc = (q[0] ** 2 + q[1] ** 2) / a2 + q[2] ** 2 / b2 - 1
    height = (-bb + math.sqrt(bb * bb - 4 * aa * cc)) / (2 * aa)
    x, y, z = [q[i] + height * u[i] for i in range(3)]
    lon = math.atan2(y, x)
    p = math.hypot(x, y)
    e2 = 1 - (1 - 1 / 298.257223563) ** 2
    lat = math.atan2(z, p * (1 - e2))
    for _ in range(5):
        n = 6_378_137.0 / math.sqrt(1 - e2 * math.sin(lat) ** 2)
        lat = math.atan2(z + e2 * n * math.sin(lat), p)
    return math.degrees(lat), math.degrees(lon)


def pixel(lat: float, lon: float) -> tuple[float, float]:
    n = 2 ** ZOOM * TILE_SIZE
    return ((lon + 180) / 360 * n,
            (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)


samples = []
tiles_needed = set()
for row in range(WIDTH):
    north = RADIUS_METERS - row * SPACING_METERS
    for column in range(WIDTH):
        east = column * SPACING_METERS - RADIUS_METERS
        x, y = pixel(*coordinate(east, north))
        samples.append((x, y))
        tiles_needed.add((int(x) // TILE_SIZE, int(y) // TILE_SIZE))
        tiles_needed.add((int(x + 1) // TILE_SIZE, int(y + 1) // TILE_SIZE))


def download(key: tuple[int, int]) -> tuple[tuple[int, int], Image.Image]:
    x, y = key
    url = f"{SOURCE}/{ZOOM}/{x}/{y}.png"
    request = urllib.request.Request(url, headers={"User-Agent": "MeuLabVision terrain builder/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        image = Image.open(io.BytesIO(response.read())).convert("RGB")
    if image.size != (TILE_SIZE, TILE_SIZE):
        raise ValueError(f"Unexpected tile size at {url}: {image.size}")
    return key, image


with ThreadPoolExecutor(max_workers=8) as pool:
    tiles = dict(pool.map(download, sorted(tiles_needed)))


def elevation_at(x: int, y: int) -> float:
    image = tiles[(x // TILE_SIZE, y // TILE_SIZE)]
    r, g, b = image.getpixel((x % TILE_SIZE, y % TILE_SIZE))
    return r * 256 + g + b / 256 - 32_768


heights = []
for x, y in samples:
    left, top = math.floor(x), math.floor(y)
    dx, dy = x - left, y - top
    nw = elevation_at(left, top)
    ne = elevation_at(left + 1, top)
    sw = elevation_at(left, top + 1)
    se = elevation_at(left + 1, top + 1)
    value = (nw * (1 - dx) + ne * dx) * (1 - dy) + (sw * (1 - dx) + se * dx) * dy
    heights.append(round(value))

if any(value < -32_768 or value > 32_767 for value in heights):
    raise ValueError("Terrain elevation exceeds Int16 range")

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
OUTPUT.write_bytes(struct.pack(f"<{len(heights)}h", *heights))
METADATA.write_text(json.dumps({
    "centerLatitude": LAT,
    "centerLongitude": LON,
    "radiusMeters": RADIUS_METERS,
    "spacingMeters": SPACING_METERS,
    "width": WIDTH,
    "centerElevationMeters": heights[(WIDTH // 2) * WIDTH + WIDTH // 2],
    "minimumElevationMeters": min(heights),
    "maximumElevationMeters": max(heights),
    "tileZoom": ZOOM,
    "source": SOURCE,
    "attribution": "Mapzen Terrain Tiles / SRTM terrain data courtesy of the U.S. Geological Survey",
}, indent=2, sort_keys=True) + "\n")
print(f"{WIDTH}×{WIDTH} elevations, {len(tiles)} tiles, "
      f"{min(heights)}–{max(heights)} m, center {heights[len(heights) // 2]} m")
