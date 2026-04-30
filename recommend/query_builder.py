MOOD_WORDS = ["감성", "분위기 좋은", "분위기", "조용한", "편안한", "노트북"]

# mood별 1차 검색어 (감성 맥락에 맞는 업종명)
MOOD_PRIMARY_QUERY = {
    "감성": ["한정식", "솥밥", "다이닝", "전통주점"],
    "조용한": ["북카페", "스터디카페", "카페"],
    "편안한": ["포차", "이자카야"],
}

# mood별 긍정 키워드 (장소명에 있으면 +점수)
MOOD_POSITIVE = {
    "감성": ["한정식", "솥밥", "다이닝", "비스트로", "레스토랑", "오마카세", "감성", "브런치"],
    "조용한": ["조용", "스터디", "북카페", "공방"],
    "편안한": ["포차", "이자카야", "호프", "막걸리"],
}

# mood별 비선호 키워드 (장소명에 있으면 -점수)
MOOD_NEGATIVE = {
    "감성": ["감자탕", "국밥", "찌개", "순대"],
    "조용한": ["노래", "클럽"],
    "편안한": [],
}

# 카테고리 기반 감점
CATEGORY_NEGATIVE = {
    "감성": ["국밥", "찌개", "감자탕", "순대"],
    "조용한": ["노래", "클럽"],
}


def clean_search_query(query):
    """카카오맵 검색용 쿼리 정제 - 형용사 제거, 업종명만 남김"""
    clean_query = query
    for word in MOOD_WORDS:
        clean_query = clean_query.replace(word, "").strip()
    if not clean_query:
        clean_query = "맛집"
    return clean_query


def get_primary_queries(mood_list, base_query):
    """
    mood 기반 1차 검색어 목록 반환
    없으면 base_query 사용
    """
    queries = []
    for mood in mood_list:
        primary = MOOD_PRIMARY_QUERY.get(mood, [])
        queries.extend(primary)

    if not queries:
        queries = [base_query]

    return queries

def score_places(places, mood_list, base_query="", max_distance=3000):
    scored = []

    for place in places:
        score = 0
        name = place["name"]
        category = place.get("category", "")
        distance = place["distance"]

        # 거리 점수 (최대 20점)
        distance_score = max(0, 20 - (distance / max_distance) * 20)
        score += distance_score

        # base_query 카테고리 일치 여부 확인
        is_category_match = True
        if base_query == "한식당" and "한식" not in category:
            is_category_match = False
        elif base_query == "카페" and "카페" not in category:
            is_category_match = False
        elif base_query == "술집" and "술집" not in category:
            is_category_match = False

        # 카테고리 불일치면 감점
        if not is_category_match:
            score -= 30

        # mood 점수
        for mood in mood_list:
            positive_keywords = MOOD_POSITIVE.get(mood, [])
            negative_keywords = MOOD_NEGATIVE.get(mood, [])
            cat_negative = CATEGORY_NEGATIVE.get(mood, [])

            # 카테고리 일치할 때만 긍정 점수
            if is_category_match and any(k in name for k in positive_keywords):
                score += 40
            if any(k in name for k in negative_keywords):
                score -= 25
            if any(k in category for k in cat_negative):
                score -= 15

        scored.append((score, place))

    scored.sort(key=lambda x: x[0], reverse=True)
    return [place for _, place in scored]