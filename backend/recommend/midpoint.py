from concurrent.futures import ThreadPoolExecutor
import math

from recommend.place import search_places
from recommend.transit import get_transit_time
from recommend.intersection import get_intersection_shape, is_within_intersection, utm_to_latlon


def find_best_midpoint(user1, user2, radius_expansion=1.0, mode1="transit", mode2="transit"):
    """
    교집합 영역 내에서 대중교통 이동시간 최적 지하철역 선택.

    user1/user2 = {"lat": ..., "lng": ..., "radius": ...}

    반환:
    {
        "area_name": "홍대입구역",
        "center_lat": 37.5573,
        "center_lng": 126.9245,
        "user1": {"time": 30, "mode": "transit"},
        "user2": {"time": 27, "mode": "transit"},
        "total_time": 57
    }
    교집합이 없거나 교집합 내 역이 없으면 None 반환 → app.py 에서 교집합 centroid 사용.
    """
    shape = get_intersection_shape(user1, user2, radius_expansion)
    if shape is None:
        return None

    # 교집합 centroid 기준으로 역 탐색
    centroid = shape.centroid
    center_lat, center_lng = utm_to_latlon(centroid.x, centroid.y)

    # 교집합 유효반경 + 여유 500m 로 역 검색 (최소 2km)
    base_radius = int(math.sqrt(shape.area / math.pi))
    stations = search_places(
        "지하철역", center_lat, center_lng,
        radius=max(base_radius + 500, 2000), size=10,
    )

    # 교집합 내부에 있는 역만 후보로 사용
    candidates = [s for s in stations if is_within_intersection(s['lat'], s['lng'], shape)]
    if not candidates:
        return None

    def calc_score(station):
        t1 = get_transit_time(user1["lat"], user1["lng"], station["lat"], station["lng"])
        t2 = get_transit_time(user2["lat"], user2["lng"], station["lat"], station["lng"])
        if t1 is None or t2 is None:
            return None, float("inf")
        total = t1 + t2
        score = total + abs(t1 - t2) * 0.5  # 이동시간 불균형 패널티
        return {
            "area_name": station["name"],
            "center_lat": station["lat"],
            "center_lng": station["lng"],
            "user1": {"time": t1, "mode": mode1},
            "user2": {"time": t2, "mode": mode2},
            "total_time": total,
        }, score

    with ThreadPoolExecutor(max_workers=5) as executor:
        results = list(executor.map(calc_score, candidates))

    best = min(results, key=lambda x: x[1])
    return best[0]  # 모든 이동시간 실패 시 None
