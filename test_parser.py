from kakao.kakao_parser import parse_kakao_txt
from nlp.rule_based import calculate_intimacy_score, get_intimacy_label, calculate_radius_expansion
from nlp.openai_analyzer import analyze_with_openai

print("\n===== OpenAI 취향 분석 테스트 =====")

files = {
    "시나리오1 친구": "kakao/test_friend.txt",
    "시나리오2 지인": "kakao/test_acquaintance.txt",
    "시나리오3 직장": "kakao/test_work.txt"
}

for name, path in files.items():
    messages = parse_kakao_txt(path)
    result = analyze_with_openai(messages)
    print(f"\n========== {name} ==========")
    print(f"만남 목적: {result['purpose']}")
    print(f"선호 음식: {result['preferred_food']}")
    print(f"피하는 음식: {result['avoided_food']}")
    print(f"장소 유형: {result['place_type']}")
    print(f"분위기: {result['mood']}")
    print(f"검색 쿼리: {result['search_query']}")


print("\n===== 친밀도 테스트 =====")

for name, path in files.items():
    messages = parse_kakao_txt(path)
    score = calculate_intimacy_score(messages)
    label = get_intimacy_label(score)
    expansion = calculate_radius_expansion(score)
    print(f"\n========== {name} ==========")
    print(f"친밀도: {score}점 ({label})")
    print(f"반경 확장 배수: x{expansion}")