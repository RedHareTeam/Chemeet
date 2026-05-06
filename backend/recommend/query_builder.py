MOOD_APPLIES_TO = ["한식당", "카페", "맛집"]

MOOD_WORDS = [
    "감성", "분위기 좋은", "분위기",
    "조용한", "편안한",
    "노트북", "작업", "스터디"
]

# mood별 1차 검색어
MOOD_PRIMARY_QUERY = {
    "감성": ["한정식", "솥밥", "다이닝", "전통주점", "비스트로", "레스토랑"],
    "조용한": ["카페"],
    "작업": ["카페"],
    "편안한": ["포차", "이자카야"],
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
    """mood 기반 1차 검색어 목록 반환, 없으면 base_query 사용"""
    
    # base_query가 특정 음식점이면 그대로 사용 
    if base_query not in MOOD_APPLIES_TO:
        return [base_query]
    
    queries = []
    for mood in mood_list:
        primary = MOOD_PRIMARY_QUERY.get(mood, [])
        queries.extend(primary)
    
    if not queries:
        queries = [base_query]
    
    return queries

def filter_by_category(places, base_query):
    """카테고리 불일치 장소 필터링 (불일치 없으면 원본 반환)"""
    result = []
    for place in places:
        category = place.get("category", "")
        if base_query == "한식당" and "한식" not in category:
            continue
        if base_query == "카페" and "카페" not in category:
            continue
        if base_query == "술집" and not any(k in category for k in ["술집", "주점", "호프"]):
            continue
        result.append(place)
    return result if result else places