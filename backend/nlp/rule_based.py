import re

EMOJI_PATTERN = re.compile(
    "[\U00010000-\U0010ffff"
    "\U0001F600-\U0001F64F"
    "\U0001F300-\U0001F5FF"
    "\U0001F680-\U0001F9FF"
    "\u2600-\u26FF"
    "\u2700-\u27BF]+",
    flags=re.UNICODE
)

WARM_EMOJIS = {'❤️', '🥰', '😍', '💕', '💗', '💓', '🫶', '😊', '☺️', '🥺'}

INFORMAL_ENDINGS = ['ㅋ', 'ㅎ', '야', '어', '지', '해', '잖아', '거든', '다고', '네', '래']
FORMAL_ENDINGS = ['요', '습니다', '니다', '세요', '드립니다', '겠습니다']

# 친밀 호칭
def has_informal_title(text):
    return bool(re.search(r'(^|\s)(야|형|언니|오빠|누나)(\s|$|,|!)', text))
# 격식 호칭
def has_formal_title(text):
    return bool(re.search(r'(님|씨|대리|과장|팀장|부장|선생님|교수님)', text))
# 새벽/늦은 밤 시간대
LATE_NIGHT_HOURS = {0, 1, 2, 3, 4, 5, 6, 7, 22, 23}


def calculate_intimacy_score(messages):
    if not messages:
        return 0

    total = len(messages)

    # 인원 수 계산
    sender_count = len(set(m['sender'] for m in messages))

    # 1. 1인당 메시지 수 점수 (25점)
    # 2명 기준 1인당 50개 = 만점, 인원 수 늘어도 공정하게 계산
    msg_per_person = total / sender_count
    msg_score = min(msg_per_person / 50, 1.0) * 25

    # 2. 반말 비율 점수 (35점)
    informal = sum(1 for m in messages if any(m['message'].endswith(e) for e in INFORMAL_ENDINGS))
    formal = sum(1 for m in messages if any(m['message'].endswith(e) for e in FORMAL_ENDINGS))
    total_style = informal + formal
    informal_ratio = informal / total_style if total_style > 0 else 0.5
    informal_score = informal_ratio * 35

    # 3. 이모지 빈도 점수 (5점)
    emoji_count = sum(len(EMOJI_PATTERN.findall(m['message'])) for m in messages)
    emoji_ratio = emoji_count / total
    emoji_score = min(emoji_ratio / 0.3, 1.0) * 5

    # 4. 친밀 이모지 점수 (10점)
    warm_count = sum(m['message'].count(e) for m in messages for e in WARM_EMOJIS)
    warm_ratio = warm_count / total
    warm_score = min(warm_ratio / 0.1, 1.0) * 10

    # 5. 호칭 패턴 점수 (15점)
    informal_title_count = sum(1 for m in messages if has_informal_title(m['message']))
    formal_title_count = sum(1 for m in messages if has_formal_title(m['message']))
    total_title = informal_title_count + formal_title_count
    if total_title == 0:
        title_score = 7.5
    else:
        informal_title_ratio = informal_title_count / total_title
        title_score = informal_title_ratio * 15

    # 6. 대화 시간대 점수 (10점)
    late_night_count = sum(
        1 for m in messages
        if int(m['time'].split(':')[0]) in LATE_NIGHT_HOURS
    )
    late_night_ratio = late_night_count / total
    time_score = min(late_night_ratio / 0.2, 1.0) * 10

    total_score = msg_score + informal_score + emoji_score + warm_score + title_score + time_score
    return round(min(max(total_score, 0), 100), 1)


def get_intimacy_label(score):
    if score >= 75:
        return "친밀"
    elif score >= 40:
        return "보통"
    elif score >= 20:
        return "낮음"
    else:
        return "매우 낮음"


def calculate_radius_expansion(intimacy_score):
    """
    친밀도에 따른 반경 확장 배수 계산
    친밀도 높을수록 반경 넓어짐 → 취향 기반 추천 범위 확대
    """
    if intimacy_score <= 40:
        return 1.0
    elif intimacy_score <= 70:
        return 1.3
    else:
        return 1.5