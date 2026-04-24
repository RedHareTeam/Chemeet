from nlp.keyword_extractor import extract_keywords, keywords_to_search_query
from kakao.kakao_parser import parse_kakao_txt
from nlp.rule_based import calculate_intimacy_score, get_intimacy_label, calculate_radius_expansion

files = {
    "시나리오1 친구": "kakao/test_friend.txt",
    "시나리오2 지인": "kakao/test_acquaintance.txt",
    "시나리오3 직장": "kakao/test_work.txt"
}

for name, path in files.items():
    messages = parse_kakao_txt(path)
    keywords = extract_keywords(messages)
    query = keywords_to_search_query(keywords)
    print(f"\n========== {name} ==========")
    print(f"선호 음식: {keywords['preferred_food']}")
    print(f"피하는 음식: {keywords['avoided_food']}")
    print(f"평소 취향: {keywords['general_preference']}")
    print(f"장소: {keywords['place']}")
    print(f"분위기: {keywords['mood']}")
    print(f"검색 쿼리: {query}")

print("\n===== 친밀도 + 양보 지수 테스트 =====")


for name, path in files.items():
    messages = parse_kakao_txt(path)
    score = calculate_intimacy_score(messages)
    label = get_intimacy_label(score)
    expansion = calculate_radius_expansion(score)
    print(f"\n========== {name} ==========")
    print(f"친밀도: {score}점 ({label})")
    print(f"반경 확장 배수: x{expansion}")