from konlpy.tag import Okt
from collections import Counter

okt = Okt()

# 음식 키워드
FOOD_KEYWORDS = {
    '파스타', '고기', '삼겹살', '스테이크', '초밥', '라멘', '피자', '버거',
    '한식', '일식', '중식', '양식', '분식', '샐러드', '샌드위치', '국밥',
    '찌개', '갈비', '치킨', '족발', '보쌈', '곱창', '해산물', '회',
    '브런치', '디저트', '케이크', '빵', '떡볶이', '냉면', '국수',
    '술', '소주', '맥주', '와인', '하이볼'
}

# 장소 키워드
PLACE_KEYWORDS = {
    '카페', '레스토랑', '식당', '맛집', '바', '펍', '이자카야',
    '루프탑', '테라스', '한강', '공원', '영화관',
    '볼링장', '노래방', '방탈출', '술집'
}

# 분위기 키워드
MOOD_KEYWORDS = {
    '조용한', '감성', '분위기', '아늑한', '힙한', '프라이빗', '뷰',
    '야경', '인스타', '넓은', '편한', '캐주얼', '고급', '특별한'
}

# 부정 패턴
NEGATIVE_PATTERNS = [
    '싫어', '별로', '질렸어', '많이 먹었', '너무 먹었',
    '지겨워', '빼고', '제외', '패스', '먹기 싫', '땡기지 않',
    '말고', '아니고', '지쳤어', '그만',
    '먹었으니까 이번엔',
    '먹었으니 이번엔' 
]
# 긍정 패턴
POSITIVE_PATTERNS = [
    '먹고 싶', '땡긴다', '땡겨', '좋아', '좋겠다', '가고 싶',
    '먹자', '어때', '괜찮', '맛있', '끌린다'
]

# 최근 메시지 기준
RECENT_MESSAGE_COUNT = 20


def extract_nouns(text):
    """형태소 분석으로 명사 추출"""
    return okt.nouns(text)

def is_negative_context(text):
    """부정 문맥 확인"""
    return any(pattern in text for pattern in NEGATIVE_PATTERNS)

def is_positive_context(text):
    """긍정 문맥 확인"""
    return any(pattern in text for pattern in POSITIVE_PATTERNS)

def extract_keywords(messages):
    """Z
    대화 메시지에서 취향 키워드 추출
    반환:
    {
        "preferred_food": [...],    # 이번 만남에서 선호
        "avoided_food": [...],      # 이번 만남에서 피하고 싶은
        "general_preference": [...], # 평소 자주 언급
        "place": [...],
        "mood": [...]
    }
    """
    total = len(messages)
    recent_messages = messages[max(0, total - RECENT_MESSAGE_COUNT):]

    preferred = Counter()
    avoided = Counter()
    general = Counter()
    place_counter = Counter()
    mood_counter = Counter()

    for i, m in enumerate(messages):
        text = m['message']
        nouns = extract_nouns(text)

        # 최근 메시지일수록 가중치 높음 (1.0 ~ 2.0)
        # 마지막 20개 메시지는 가중치 3배
        is_recent = m in recent_messages
        recency_weight = int((1 + (i / total) * 10) * (3 if is_recent else 1))

        for noun in nouns:
            if noun in PLACE_KEYWORDS:
                place_counter[noun] += 1

        for mood_word in MOOD_KEYWORDS:
            if mood_word in text:
                mood_counter[mood_word] += 1

        # 음식 키워드 문맥 분석
        food_in_text = [n for n in nouns if n in FOOD_KEYWORDS]
        if not food_in_text:
            continue

        is_negative = is_negative_context(text)
        is_positive = is_positive_context(text)
        is_recent = m in recent_messages

        for food in food_in_text:
            general[food] += 1

            if is_negative:
                avoided[food] += recency_weight
            elif is_positive:
                weight = recency_weight * 2 if is_recent else recency_weight
                preferred[food] += weight
            else:
                # 긍/부정 불명확 → 최근이면 preferred에 약하게 반영
                if is_recent:
                    preferred[food] += 1

    # avoided에 있는 건 preferred에서 제거
    for food in list(avoided.keys()):
        if food in preferred:
            del preferred[food]

     # 마지막 10개 메시지에서 나온 키워드 1순위로
    last_messages = messages[max(0, total - 10):]
    last_preferred = []

    for m in last_messages:
        text = m['message']
        nouns = extract_nouns(text)
        for noun in nouns:
            if noun in FOOD_KEYWORDS and noun not in avoided:
                if not is_negative_context(text):
                    if noun not in last_preferred:
                        last_preferred.append(noun)

    # 나머지 preferred (last_preferred 제외, avoided 제외)
    rest_preferred = [w for w, _ in preferred.most_common()
                      if w not in last_preferred and w not in avoided]

    return {
        "preferred_food": last_preferred + rest_preferred,
        "avoided_food": [w for w, _ in avoided.most_common()],
        "general_preference": [w for w, _ in general.most_common()],
        "place": [w for w, _ in place_counter.most_common()],
        "mood": [w for w, _ in mood_counter.most_common()]
    }


def keywords_to_search_query(keywords):
    """
    추출된 키워드를 카카오맵 검색 쿼리로 변환
    preferred_food 우선 → place → mood
    """
    query_parts = []

    # preferred_food 우선, 없으면 general_preference
    food_source = keywords['preferred_food'] or keywords['general_preference']
    if food_source:
        food = [f for f in food_source if f not in ('술', '소주', '맥주', '와인', '하이볼')]
        if food:
            query_parts.append(food[0])

    # 장소 카테고리
    PLACE_CATEGORY = {'카페', '레스토랑', '식당', '바', '펍', '술집', '이자카야', '루프탑'}
    place_category = [p for p in keywords['place'] if p in PLACE_CATEGORY]

    if place_category:
        query_parts.append(place_category[0])
    elif any(f in food_source for f in ('술', '소주', '맥주', '와인', '하이볼')):
        query_parts.append('술집')

    # 분위기
    if keywords['mood']:
        query_parts.append(keywords['mood'][0])

    if not query_parts:
        query_parts.append('맛집')

    return ' '.join(query_parts)