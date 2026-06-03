import requests
import json

BASE_URL = "http://localhost:5000"

# ── Step 1: /analyze ──────────────────────────────────
print("=" * 50)
print("Step 1: /analyze (test_3people.txt)")
print("=" * 50)

# test_acquaintance.txt 로 먼저
with open("tests/samples/test_friend.txt", encoding="utf-8") as f:
    txt_content = f.read()

res = requests.post(
    f"{BASE_URL}/analyze",
    json={"txt_content": txt_content},
    headers={"Content-Type": "application/json; charset=utf-8"}
)

if res.status_code != 200:
    print(f"오류: {res.status_code}")
    print(res.json())
    exit()

analysis = res.json()
print(f"참여자:          {analysis['senders']}")
print(f"친밀도:          {analysis['intimacy_score']} ({analysis['intimacy_label']})")
print(f"purpose:         {analysis['purpose']}")
print(f"place_type:      {analysis['place_type']}")
print(f"secondary:       {analysis['secondary_place_type']}")
print(f"preferred_food:  {analysis['preferred_food']}")
print(f"avoided_food:    {analysis['avoided_food']}")
print(f"mood:            {analysis['mood']}")

# ── Step 2: /recommend ───────────────────────────────
print()
print("=" * 50)
print("Step 2: /recommend")
print("=" * 50)

recommend_data = {
# 강남 시나리오 (판교 + 강남 + 잠실)
"users": [
    {"lat": 37.4979, "lng": 127.0276, "radius": 3000},  # 강남
    {"lat": 37.5172, "lng": 127.0473, "radius": 3000},  # 삼성
],
    "purpose":              analysis["purpose"],
    "place_type":           analysis["place_type"][0] if analysis["place_type"] else "",
    "secondary_place_type": analysis["secondary_place_type"][0] if analysis["secondary_place_type"] else "",
    "preferred_food":       analysis["preferred_food"],
    "mood":                 analysis["mood"],
    "intimacy_score":       analysis["intimacy_score"],
}

print(f"요청 place_type:  {recommend_data['place_type']}")
print(f"요청 secondary:   {recommend_data['secondary_place_type']}")
print(f"요청 purpose:     {recommend_data['purpose']}")
print(f"요청 preferred:   {recommend_data['preferred_food']}")

res2 = requests.post(
    f"{BASE_URL}/recommend",
    json=recommend_data,
    headers={"Content-Type": "application/json; charset=utf-8"}
)

if res2.status_code != 200:
    print(f"오류: {res2.status_code}")
    print(res2.json())
    exit()

result = res2.json()
print()
print(f"교집합 여부: {result['has_intersection']}")
print(f"지역:        {result.get('area_name', '')}")
print(f"날씨:        {result.get('weather', {}).get('description', '')}")

print(f"\n1차 장소 ({recommend_data['place_type']}):")
for p in result["places"]:
    print(f"  - {p['name']} | {p['category']} | {p['distance']}m")

if result.get("secondary_places"):
    print(f"\n2차 장소 ({recommend_data['secondary_place_type']}):")
    for p in result["secondary_places"]:
        print(f"  - {p['name']} | {p['category']} | {p['distance']}m")
else:
    print(f"\n2차 장소: 없음")