from flask import Flask, request, jsonify
from kakao.kakao_parser import parse_kakao_txt
from nlp.openai_analyzer import analyze_with_openai
from nlp.rule_based import calculate_intimacy_score, get_intimacy_label, calculate_radius_expansion
import os
import tempfile
from recommend.intersection import calculate_intersection
from recommend.place import search_places
from recommend.query_builder import clean_search_query, get_primary_queries, filter_by_category
from recommend.weather import get_weather
from recommend.midpoint import find_best_midpoint

app = Flask(__name__)

@app.route('/')
def index():
    return jsonify({"status": "Chemeet API 서버 실행 중"})


@app.route('/analyze', methods=['POST'])
def analyze():
    if 'file' not in request.files:
        return jsonify({"error": "파일이 없습니다"}), 400

    file = request.files['file']

    if file.filename == '':
        return jsonify({"error": "파일명이 없습니다"}), 400

    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='wb') as tmp:
        file.save(tmp)
        tmp_path = tmp.name

    try:
        messages = parse_kakao_txt(tmp_path)

        if not messages:
            return jsonify({"error": "파싱된 메시지가 없습니다"}), 400
        # OpenAI 취향 분석
        keywords = analyze_with_openai(messages)

        # 친밀도 분석용
        INTIMACY_MAX_MESSAGES = 100
        messages_for_intimacy = messages[-INTIMACY_MAX_MESSAGES:]

        intimacy_score = calculate_intimacy_score(messages_for_intimacy)
        intimacy_label = get_intimacy_label(intimacy_score)
        radius_expansion = calculate_radius_expansion(intimacy_score)

        return jsonify({
            "senders": keywords['senders'],
            "intimacy_score": intimacy_score,
            "intimacy_label": intimacy_label,
            "radius_expansion": radius_expansion,
            "purpose": keywords['purpose'],
            "preferred_food": keywords['preferred_food'],
            "avoided_food": keywords['avoided_food'],
            "place_type": keywords['place_type'],
            "secondary_place_type": keywords['secondary_place_type'],
            "mood": keywords['mood'],
            "search_query": keywords['search_query']
        })

    finally:
        os.remove(tmp_path)

@app.route('/recommend', methods=['POST'])
def recommend():
    data = request.get_json()

    if not data:
        return jsonify({"error": "데이터가 없습니다"}), 400

    user1 = data.get('user1')
    user2 = data.get('user2')
    search_query = data.get('search_query', '맛집')
    mood = data.get('mood', [])
    intimacy_score = data.get('intimacy_score', 50)

    if not user1 or not user2:
        return jsonify({"error": "user1, user2 좌표가 필요합니다"}), 400

    # 반경 확장 배수
    radius_expansion = calculate_radius_expansion(intimacy_score)

    # 교집합 계산
    intersection = calculate_intersection(user1, user2, radius_expansion)

    # 최적 중간지점 계산 (대중교통 시간 기반)
    midpoint = find_best_midpoint(user1, user2)

    if midpoint:
        center_lat = midpoint["center_lat"]
        center_lng = midpoint["center_lng"]
        area_name = midpoint["area_name"]
    else:
        # fallback: 교집합 중심
        center_lat = intersection["center_lat"]
        center_lng = intersection["center_lng"]
        area_name = None

    search_radius = intersection["search_radius"]

    # 날씨 정보 가져오기
    weather = get_weather(center_lat, center_lng)
    condition = weather.get("condition", "clear")

    # 날씨 나쁠 때 반경 줄이기 + 역 근처
    if condition in ["rain", "snow", "thunder"]:
        search_radius = min(search_radius, 1500)
        stations = search_places("지하철역", center_lat, center_lng, radius=2000, size=3)
        if stations:
            nearest = stations[0]
            center_lat = nearest['lat']
            center_lng = nearest['lng']
            area_name = nearest['name']
    
    # 장소 검색
    base_query = clean_search_query(search_query)
    primary_queries = get_primary_queries(mood, base_query)

    all_places = []
    for q in primary_queries:
        results = search_places(q, center_lat, center_lng, radius=search_radius, size=10)
        all_places.extend(results)

    # 중복 제거
    seen = set()
    unique_places = []
    for p in all_places:
        if p['name'] not in seen:
            seen.add(p['name'])
            unique_places.append(p)

    # 카테고리 필터링
    filtered = filter_by_category(unique_places, base_query)
    top_places = filtered[:5]

    return jsonify({
        "has_intersection": intersection["has_intersection"],
        "area_name": area_name,
        "center_lat": center_lat,
        "center_lng": center_lng,
        "search_radius": search_radius,
        "weather": weather,
        "user1_transit": midpoint["user1"] if midpoint else None,
        "user2_transit": midpoint["user2"] if midpoint else None,
        "total_time": midpoint["total_time"] if midpoint else None,
        "places": top_places
    })
    
if __name__ == '__main__':
    app.run(debug=True)