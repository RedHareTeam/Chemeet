# Chemeet Backend

카카오톡 대화 분석 기반 모임 장소 추천 앱 Chemeet의 백엔드 서버

---

## 개발 단계

| 단계 | 작업 | 상태 |
|------|------|------|
| 1 | 환경 구축 | ✅ 완료 |
| 2 | 카카오톡 대화 파싱 | ✅ 완료 |
| 3 | OpenAI 기반 취향 분석 | ✅ 완료 |
| 4 | 친밀도 모듈 | ✅ 완료 |
| 5 | Flask /analyze 엔드포인트 | ✅ 완료 |
| 6 | 교집합 계산 (Shapely) | ⬜ 미완 |
| 7 | 카카오맵 장소 추천 + /recommend | ⬜ 미완 |
| 8 | 날씨 필터 연동 | ⬜ 미완 |
| 9 | 전체 통합 테스트 | ⬜ 미완 |

---

## 프로젝트 구조

```
chemeet-backend/
├── app.py                      # Flask 서버, API 엔드포인트
├── kakao/
│   ├── kakao_parser.py         # 카카오톡 txt 파싱
│   └── test_*.txt              # 테스트용 시나리오 데이터
├── nlp/
│   ├── openai_analyzer.py      # OpenAI 기반 취향 분석
│   └── rule_based.py           # 친밀도 산출 모듈
└── requirements.txt
```

---

## API 명세

### POST /analyze
카카오톡 대화 파일 분석

**입력**
- 형식: multipart/form-data
- 파라미터: file (카카오톡 대화 txt 파일)

**출력**
```json
{
  "senders": ["희주", "재영"],
  "intimacy_score": 86.0,
  "intimacy_label": "친밀",
  "radius_expansion": 1.5,
  "purpose": "친목",
  "preferred_food": ["한식"],
  "avoided_food": ["파스타"],
  "place_type": ["한식당"],
  "secondary_place_type": ["카페"],
  "mood": ["감성 있는", "조용한"],
  "search_query": "감성 한식당"
}
```

### POST /recommend
장소 추천 (7단계 구현 예정)

**입력**
```json
{
  "user1": {"lat": 37.5665, "lng": 126.9780, "radius": 3000},
  "user2": {"lat": 37.4979, "lng": 127.0276, "radius": 3000},
  "search_query": "감성 한식당",
  "intimacy_score": 86.0
}
```

---

## 기술 결정 사항

| 항목 | 결정 |
|------|------|
| 취향 분석 | OpenAI gpt-4o-mini (KoBERT 대체) |
| 친밀도 | 규칙 기반 (반말 비율, 메시지 수, 호칭, 시간대) |
| 인원 | 2명 기반, 3명 이상 추후 확장 |
| 대화 데이터 | 분석 후 즉시 삭제 |