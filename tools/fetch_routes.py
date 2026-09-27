"""Достаёт из OpenStreetMap (Overpass API) координаты вершин, хижин и точек
в горах над Алматы, чтобы команда вручную заполнила points в assets/data/routes.json.

Запуск:  python3 tools/fetch_routes.py > osm_points.csv
Данные OSM распространяются по лицензии ODbL — указывайте «© участники OpenStreetMap».
Перед тем как поставить verified: true, каждую точку проверьте на карте.
"""
import csv
import json
import sys
import urllib.parse
import urllib.request

# Предгорья и хребты Заилийского Алатау над Алматы
BBOX = (43.00, 76.80, 43.25, 77.25)  # south, west, north, east

QUERY = f"""
[out:json][timeout:60];
(
  node["natural"="peak"]["name"]({BBOX[0]},{BBOX[1]},{BBOX[2]},{BBOX[3]});
  node["natural"="saddle"]["name"]({BBOX[0]},{BBOX[1]},{BBOX[2]},{BBOX[3]});
  node["tourism"~"alpine_hut|wilderness_hut"]({BBOX[0]},{BBOX[1]},{BBOX[2]},{BBOX[3]});
  node["waterway"="waterfall"]["name"]({BBOX[0]},{BBOX[1]},{BBOX[2]},{BBOX[3]});
  node["barrier"="lift_gate"]({BBOX[0]},{BBOX[1]},{BBOX[2]},{BBOX[3]});
);
out body;
"""

INTERESTING = ["Фурманов", "Мынжылк", "Кок-Жайля", "Шымбулак", "Медеу", "Furmanov", "Mynzhylky", "Kok-Zhailau"]


def main() -> None:
    data = urllib.parse.urlencode({"data": QUERY}).encode()
    req = urllib.request.Request(
        "https://overpass-api.de/api/interpreter",
        data=data,
        headers={"User-Agent": "TauBagdar-hackathon/0.1 (route verification)"},
    )
    with urllib.request.urlopen(req, timeout=90) as r:
        elements = json.load(r)["elements"]

    w = csv.writer(sys.stdout)
    w.writerow(["interesting", "kind", "name", "ele", "lat", "lon", "osm_id"])
    for e in sorted(elements, key=lambda x: x.get("tags", {}).get("name", "")):
        tags = e.get("tags", {})
        name = tags.get("name:ru") or tags.get("name", "")
        kind = tags.get("natural") or tags.get("tourism") or tags.get("waterway") or tags.get("barrier")
        mark = "*" if any(k.lower() in name.lower() for k in INTERESTING) else ""
        w.writerow([mark, kind, name, tags.get("ele", ""), f"{e['lat']:.5f}", f"{e['lon']:.5f}", e["id"]])


if __name__ == "__main__":
    main()
