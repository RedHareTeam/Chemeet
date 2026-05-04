# Chemeet Backend

---

## 개발 현황

| 단계 | 작업 | 상태 |
|------|------|------|
| 1~8 | 환경 구축 / 파싱 / 분석 / 추천 / 날씨 | ✅ 완료 |
| 9 | 대중교통 기반 중간지점 (ODsay) | ✅ 완료 |
| 10 | 3~4명 확장 | ⬜ 예정 |
| 11 | Firebase 방문 히스토리 | ⬜ 예정 |

---

## 프로젝트 구조

```
chemeet-backend/
├── app.py
├── kakao/
│   └── kakao_parser.py
├── nlp/
│   ├── openai_analyzer.py
│   └── rule_based.py
└── recommend/
    ├── intersection.py
    ├── midpoint.py       # 대중교통 기반 최적 중간지점 선택
    ├── place.py
    ├── query_builder.py
    ├── transit.py        # ODsay 대중교통 이동시간
    └── weather.py
```

---

## API 명세

### POST /analyze
카카오톡 대화 파일 업로드 → 취향 + 친밀도 분석

**입력** `multipart/form-data`
- `file`: 카카오톡 대화 내보내기 txt 파일

**출력**
```json
{
  "senders": ["희주", "재영"],
  "intimacy_score": 77.5,
  "intimacy_label": "친밀",
  "radius_expansion": 1.5,
  "purpose": "친목",
  "preferred_food": ["피자"],
  "avoided_food": ["라멘"],
  "place_type": ["피자집"],
  "secondary_place_type": ["카페"],
  "mood": ["감성", "조용한"],
  "search_query": "감성 피자집"
}
```

---

### POST /recommend
두 사람 위치 + 분석 결과 → 중간지점 + 장소 추천

**입력** `application/json`
```json
{
  "user1": {"lat": 37.5665, "lng": 126.9780, "radius": 3000},
  "user2": {"lat": 37.4979, "lng": 127.0276, "radius": 3000},
  "search_query": "감성 피자집",
  "mood": ["감성"],
  "intimacy_score": 77.5
}
```

**출력**
```json
{
  "has_intersection": true,
  "area_name": "서강대역 경의중앙선",
  "center_lat": 37.5521,
  "center_lng": 126.9355,
  "search_radius": 3484,
  "user1_transit": {"time": 7, "mode": "transit"},
  "user2_transit": {"time": 7, "mode": "transit"},
  "total_time": 14,
  "weather": {
    "condition": "clear",
    "temp": 18.9,
    "description": "맑음"
  },
  "places": [
    {
      "name": "피제리아더키",
      "address": "서울 마포구 광성로 42-1",
      "category": "음식점 > 양식 > 피자",
      "lat": 37.5496,
      "lng": 126.9377,
      "url": "https://place.map.kakao.com/561289275",
      "distance": 340
    }
  ]
}
```

---

### 호출 순서
```
1. 대화 파일 업로드 → POST /analyze → 분석 결과 저장
2. 두 명 지도에서 원 그리기 완료
3. POST /recommend → 중간지점 + 장소 추천 표시
```

### 주요 필드 활용

| 필드 | 용도 |
|------|------|
| `intimacy_score` | 지도 원 색상/투명도 시각화 (0~100) |
| `radius_expansion` | 지도 원 크기 조정 배수 (1.0 / 1.3 / 1.5) |
| `area_name` | 중간지점 역 이름 ("서강대역에서 만나요") |
| `user1_transit.time` | A의 대중교통 이동시간 (분) |
| `user2_transit.time` | B의 대중교통 이동시간 (분) |
| `total_time` | 두 사람 이동시간 합산 (분) |
| `secondary_place_type` | 2차 장소 별도 UI 표시 (예: 식사 후 카페) |
| `weather.condition` | 날씨 아이콘 표시 |
| `places` | 추천 장소 카드 (최대 5개) |

### 응답 시간 참고
- `/analyze`: 약 3~5초 (OpenAI API) → 로딩 인디케이터 필요
- `/recommend`: 약 2~4초 (ODsay API 호출 포함)

### 좌표/반경 입력 형식
```json
{ "lat": 37.5665, "lng": 126.9780, "radius": 3000 }
```
- `radius` 단위: 미터
- Flutter 지도에서 원 그릴 때 중심 좌표 + 반경 추출해서 전달

### 날씨 condition 값
| 값 | 의미 |
|----|------|
| `clear` | 맑음 |
| `clouds` | 흐림 |
| `rain` | 비 |
| `snow` | 눈 |
| `thunder` | 천둥번개 |

### 중간지점 선택 방식
두 사람 중간 좌표 기준 반경 5km 내 지하철역 후보 탐색 후,
각 역까지 대중교통 이동시간 합산 + 공정성(시간 차이) 가중치로 최적 역 선택.

> **fallback**: ODsay 응답 실패 시 교집합 중심 좌표로 대체