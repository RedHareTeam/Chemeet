from recommend.place import search_places
from recommend.transit import get_transit_time

def find_best_midpoint(user1, user2, mode1="transit", mode2="transit"):
    """
    두 사용자 기준 최적 중간지점 역 선택
    
    user1 = {"lat": 37.5573, "lng": 126.9245, "radius": 3000}
    mode = "transit" or "car" (car는 추후 카카오모빌리티 연동)
    
    반환:
    {
        "area_name": "홍대입구역",
        "center_lat": 37.5573,
        "center_lng": 126.9245,
        "user1": {"time": 30, "mode": "transit"},
        "user2": {"time": 27, "mode": "transit"},
        "total_time": 57
    }
    """
    # 두 사람 중간 좌표 기준으로 후보 역 검색
    mid_lat = (user1["lat"] + user2["lat"]) / 2
    mid_lng = (user1["lng"] + user2["lng"]) / 2

    stations = search_places("지하철역", mid_lat, mid_lng, radius=5000, size=5)

    if not stations:
        return None

    best = None
    best_score = float("inf")

    for station in stations:
        s_lat = station["lat"]
        s_lng = station["lng"]

        # 각 유저 → 역 이동시간
        t1 = get_transit_time(user1["lat"], user1["lng"], s_lat, s_lng)
        t2 = get_transit_time(user2["lat"], user2["lng"], s_lat, s_lng)

        if t1 is None or t2 is None:
            continue

        total = t1 + t2
        balance = abs(t1 - t2)
        score = total + (balance * 0.5)  # 공정성 가중치

        if score < best_score:
            best_score = score
            best = {
                "area_name": station["name"],
                "center_lat": s_lat,
                "center_lng": s_lng,
                "user1": {"time": t1, "mode": mode1},
                "user2": {"time": t2, "mode": mode2},
                "total_time": total
            }

    return best