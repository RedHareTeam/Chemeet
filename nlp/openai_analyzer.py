import os
from openai import OpenAI
from dotenv import load_dotenv
import json

load_dotenv()

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

PLACE_TYPE_MAP = {
    "한식": "한식당",
    "파스타": "파스타집",
    "피자": "피자집",
    "라멘": "라멘집",
    "술": "술집",
    "카페": "카페",
    "바": "바",
    "이자카야": "이자카야",
    "스터디": "스터디카페"
}

# avoided_food → place_type 매핑 (보정용)
FOOD_PLACE_MAP = {
    "라멘": "라멘집",
    "파스타": "파스타집",
    "피자": "피자집",
    "고기": "고깃집",
    "한식": "한식당",
}

PURPOSE_MOOD_MAP = {
    ("친목", "한식당"): "감성",
    ("친목", "카페"): "감성",
    ("친목", "파스타집"): "분위기 좋은",
    ("친목", "라멘집"): "감성",
    ("친목", "피자집"): "감성",
    ("술자리", "술집"): "편안한",
    ("술자리", "이자카야"): "편안한",
    ("업무미팅", "카페"): "조용한",
    ("데이트", "파스타집"): "분위기 좋은",
    ("데이트", "레스토랑"): "분위기 좋은",
}

MOOD_NORMALIZE = {
    "감성": "감성",
    "감성 있는": "감성",
    "분위기": "감성",
    "분위기 있는": "감성",
    "분위기 좋은": "감성",
    "조용한": "조용한",
    "조용": "조용한",
    "아늑한": "조용한",
    "작업": "작업",
    "노트북": "작업",
    "노트북 가능한": "작업",
    "콘센트": "작업",
    "편안한": "편안한",
    "편한": "편안한",
}


def detect_purpose(conversation):
    if any(word in conversation for word in ["노트북", "회의", "미팅", "업무", "협업"]):
        return "업무미팅"
    if any(word in conversation for word in ["기념일", "데이트"]):
        return "데이트"
    if any(word in conversation for word in ["술 한잔", "한잔 하자", "술이나", "한잔할"]):
        return "술자리"
    return "친목"


def has_strong_signal(conversation, keywords, threshold=2):
    """키워드가 threshold번 이상 등장해야 강한 신호로 판단"""
    return sum(conversation.count(k) for k in keywords) >= threshold


def make_search_query(purpose, main_place, conversation, mood):

    # 1순위: 노트북/업무 신호
    if any(word in conversation for word in ["노트북", "작업", "콘센트", "와이파이", "미팅 가능"]):
        return "노트북 카페"

    # 2순위: 술자리
    if purpose == "술자리":
        return "술집 맛집"

    # 3순위: 음식 중심 신호 (2번 이상 언급)
    if has_strong_signal(conversation, ["든든", "국물", "고기 먹고"]):
        return f"{main_place} 맛집"

    # 4순위: 감성/분위기 신호 (2번 이상 언급)
    if has_strong_signal(conversation, ["감성", "분위기", "오랜만"]) or \
       any(m in ["감성", "감성 있는", "분위기 있는"] for m in mood):
        return f"감성 {main_place}"

    # 5순위: purpose 기반 기본값
    auto_mood = PURPOSE_MOOD_MAP.get((purpose, main_place), "")
    return f"{auto_mood} {main_place}".strip() if auto_mood else main_place


def analyze_with_openai(messages):
    """
    OpenAI API로 대화 분석
    취향 키워드 추출 (preferred_food, avoided_food, place_type, mood)
    """
    conversation = "\n".join(
        f"[{m['sender']}] {m['message']}" for m in messages
    )

    senders = list(dict.fromkeys(m['sender'] for m in messages))
    sender_info = f"대화 참여자: {senders[0]}, {senders[1]}" if len(senders) >= 2 else ""

    purpose = detect_purpose(conversation)

    prompt = f"""
다음은 두 사람의 카카오톡 대화입니다.

{sender_info}

[예시]
대화:
[재영] 저번에 라멘 먹었으니까 이번엔 다른 거 먹자
[재영] 나 요즘 피자 땡기던데
[희주] 오 피자 좋지

올바른 분석:
{{
  "preferred_food": ["피자"],
  "avoided_food": ["라멘"],
  "place_type": ["피자집"],
  "secondary_place_type": [],
  "mood": []
}}

이제 아래 실제 대화를 분석해주세요:

대화:
{conversation}

[분석 규칙]

place_type 규칙:
- 1차 목적 장소만 1개 선택
- "밥 먹고 카페", "2차로 카페"처럼 순서 있으면 식당만 place_type, 카페는 secondary_place_type
- 반드시 아래 중에서만: 카페, 술집, 한식당, 파스타집, 라멘집, 피자집, 바, 스터디카페, 이자카야

secondary_place_type 규칙:
- 2차 장소 있으면 여기에 넣기
- 없으면 빈 배열

mood 규칙:
- 대화에서 직접 표현된 경우에만 추출
- "감성", "분위기", "조용한", "편안한" 같은 표현이 장소 맥락에서 나오면 추출
- 없으면 빈 배열

avoided_food 규칙:
- avoided는 preferred에 절대 포함 금지
- "저번에 ~먹었으니까", "~말고", "~많이 먹어서" → avoided
- "저번에 ~먹었으니까 이번엔" → 앞의 음식은 avoided, 뒤의 음식은 preferred
- 최근 대화 우선

JSON으로만 응답:
{{
  "preferred_food": [],
  "avoided_food": [],
  "place_type": [],
  "secondary_place_type": [],
  "mood": []
}}
"""

    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.3
    )

    result = response.choices[0].message.content.strip()

    try:
        if result.startswith("```"):
            result = result.split("```")[1]
            if result.startswith("json"):
                result = result[4:]
        parsed = json.loads(result)

        # PLACE_TYPE_MAP 변환
        parsed["place_type"] = [
            PLACE_TYPE_MAP.get(p, p)
            for p in parsed.get("place_type", [])
        ]
        parsed["secondary_place_type"] = [
            PLACE_TYPE_MAP.get(p, p)
            for p in parsed.get("secondary_place_type", [])
        ]

        # 1. avoided에 있는 음식은 preferred에서 제거
        preferred = parsed.get("preferred_food", [])
        avoided = parsed.get("avoided_food", [])
        parsed["preferred_food"] = [f for f in preferred if f not in avoided]

        # 2. place_type 최대 1개
        if parsed["preferred_food"]:
            # 최근 언급 음식 우선
            top_food = parsed["preferred_food"][-1]
            if top_food in FOOD_PLACE_MAP:
                parsed["place_type"] = [FOOD_PLACE_MAP[top_food]]

        parsed["place_type"] = parsed["place_type"][:1]

        # 3. avoided_food 기반 place_type 보정
        for food in avoided:
            bad_place = FOOD_PLACE_MAP.get(food)
            if bad_place and bad_place in parsed["place_type"]:
                parsed["place_type"] = [p for p in parsed["place_type"] if p != bad_place]

        # place_type 비었으면 preferred_food 기반으로 채우기
        if not parsed["place_type"] and parsed["preferred_food"]:
            top_food = parsed["preferred_food"][0]
            if top_food in FOOD_PLACE_MAP:
                parsed["place_type"] = [FOOD_PLACE_MAP[top_food]]

        # 4. mood 표준화 + 중복 제거
        parsed["mood"] = list(dict.fromkeys(
            MOOD_NORMALIZE.get(m, m) for m in parsed.get("mood", [])
        ))

        # 5. search_query 생성
        main_place = parsed["place_type"][0] if parsed["place_type"] else "맛집"
        parsed["search_query"] = make_search_query(
            purpose, main_place, conversation, parsed.get("mood", [])
        )
        parsed["search_query"] = parsed["search_query"].replace(',', '').strip()

        parsed['purpose'] = purpose
        parsed['senders'] = senders
        return parsed

    except json.JSONDecodeError:
        return {
            "purpose": purpose,
            "preferred_food": [],
            "avoided_food": [],
            "place_type": [],
            "secondary_place_type": [],
            "mood": [],
            "search_query": "맛집",
            "senders": senders
        }