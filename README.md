# Chemeet

카카오톡 대화 분석 기반 모임 장소 추천 앱

---

## 남은 작업

- 3~4명 확장
- 방문 히스토리
- 투표 동점 처리

---

## 프로젝트 구조

```
Chemeet/
├── backend/
│   ├── app.py                      # Flask 서버, /analyze /recommend 엔드포인트
│   ├── kakao/
│   │   ├── __init__.py
│   │   └── kakao_parser.py         # 카카오톡 txt 파일 파싱
│   ├── nlp/
│   │   ├── __init__.py
│   │   ├── openai_analyzer.py      # GPT-4o-mini 취향 키워드 추출
│   │   └── rule_based.py           # 친밀도 점수 계산 (반말 비율, 메시지 수 등)
│   ├── recommend/
│   │   ├── __init__.py
│   │   ├── intersection.py         # 두 사용자 이동 가능 구역 교집합 계산 (Shapely)
│   │   ├── midpoint.py             # 대중교통 시간 기반 최적 중간지점 역 선택
│   │   ├── place.py                # 카카오맵 로컬 API 장소 검색
│   │   ├── query_builder.py        # 검색 쿼리 생성 및 카테고리 필터링
│   │   ├── transit.py              # ODsay API 대중교통 이동시간 계산
│   │   └── weather.py              # OpenWeatherMap 날씨 정보
│   └── tests/
│       ├── samples/                # 테스트용 카카오톡 대화 파일 (친구/지인/직장)
│       ├── test_parser.py          # 파싱 / 취향분석 / 친밀도 / 교집합 단위 테스트
│       └── test_recommend.py       # /recommend 엔드포인트 통합 테스트
│
└── lib/
    ├── main.dart                   # 앱 시작점, Firebase/.env 초기화, 첫 화면 분기
    ├── firebase_options.dart       # Firebase 플랫폼별 설정
    ├── app_theme.dart              # 공통 색상/텍스트/컴포넌트 테마 정의
    ├── screens/
    │   ├── auth_screen.dart        # 로그인/회원가입
    │   ├── room_list_screen.dart   # 내 방 목록 조회, 방 생성/입장
    │   ├── room_home_screen.dart   # 방 홈, 친밀도/키워드/약속 상태 표시
    │   ├── upload_screen.dart      # 대화 txt 업로드 및 분석 요청
    │   ├── analyzing_screen.dart   # 분석 진행 화면
    │   ├── date_setting_screen.dart# 약속 날짜/시간 설정
    │   ├── map_screen.dart         # 카카오맵 원 그리기 및 장소 검색 요청
    │   └── place_screen.dart       # 후보 장소 투표 및 최종 장소 확정
    ├── services/
    │   ├── auth_service.dart       # Firebase Auth 및 사용자 정보 처리
    │   ├── room_service.dart       # 방 생성/입장/조회/히스토리 저장
    │   ├── circle_service.dart     # 원 좌표 저장, 장소 저장, 상태 변경
    │   ├── vote_service.dart       # 장소 투표 처리
    │   └── place_service.dart      # 지도 기반 주변 장소 검색
    └── widgets/
        └── kakao_map_webview.dart  # 카카오맵 웹뷰, 원 그리기/표시
```

---

## API 명세

### POST /analyze
카카오톡 대화 파일 → 취향 + 친밀도 분석

**입력** `application/json`
```json
{ "txt_content": "카카오톡 대화 내용 문자열" }
```

**출력**
```json
{
  "senders": ["희주", "재영"],
  "partner_name": "재영",
  "intimacy_score": 77.5,
  "intimacy_label": "친밀",
  "radius_expansion": 1.5,
  "purpose": "친목",
  "preferred_food": ["피자"],
  "avoided_food": ["라멘"],
  "place_type": ["피자집"],
  "secondary_place_type": ["카페"],
  "mood": ["감성", "조용한"],
  "search_query": "감성 피자집",
  "keywords": ["감성", "조용한", "피자집"]
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

## 프론트 연동 가이드

### 호출 순서
```
1. 대화 파일 업로드 (둘 중 한 명) → POST /analyze → 분석 결과 Firestore 저장
2. 두 명 지도에서 원 그리기 완료
3. 장소 추천 받기 버튼 (한 명만) → POST /recommend → 장소 목록 Firestore 저장 → 투표 화면
```

### 주요 필드 활용

| 필드 | 용도 |
|------|------|
| `intimacy_score` | 지도 원 색상/투명도 시각화 (0~100) |
| `radius_expansion` | 지도 원 크기 조정 배수 (1.0 / 1.3 / 1.5) |
| `keywords` | 방 홈 태그 표시 (#감성 #피자집) |
| `partner_name` | 상대방 이름 표시 |
| `area_name` | 중간지점 역 이름 ("서강대역에서 만나요") |
| `user1_transit.time` | A 대중교통 이동시간 (분) |
| `user2_transit.time` | B 대중교통 이동시간 (분) |
| `total_time` | 두 사람 이동시간 합산 (분) |
| `secondary_place_type` | 2차 장소 별도 표시 (예: 식사 후 카페) |
| `weather.condition` | 날씨 아이콘 표시 |
| `places` | 추천 장소 카드 (최대 20개) |

### 응답 시간
- `/analyze`: 약 3~5초 (OpenAI API)
- `/recommend`: 약 3~5초 (ODsay 병렬 호출)

### 날씨 condition 값
| 값 | 의미 |
|----|------|
| `clear` | 맑음 |
| `clouds` | 흐림 |
| `rain` | 비 |
| `snow` | 눈 |
| `thunder` | 천둥번개 |

---

## DB 구조 (Firestore)

```
users/{userId}
├── userName: string
└── rooms: [roomId, ...]

rooms/{roomId}
├── createdBy: string
├── members: [userId, ...]
├── memberNames: { userId: userName }
├── roomTitle: string
├── inviteCode: string
├── maxMembers: number
├── status: string                # waiting / drawing / voting / confirmed / idle
├── intimacyScore: number
├── keywords: [string, ...]
├── partnerName: string
├── searchQuery: string
├── mood: [string, ...]
├── appointmentDate: timestamp
├── places: [Map, ...]
├── confirmedPlace: Map
└── createdAt: timestamp

rooms/{roomId}/circles/{userId}
├── lat, lng, radius: number
└── updatedAt: timestamp

rooms/{roomId}/votes/{userId}
└── selectedPlaceId: string

rooms/{roomId}/history/{historyId}
├── confirmedPlace: Map
├── members: [userId, ...]
├── appointmentDate: timestamp
└── date: timestamp
```

---

## 상태 흐름

```
waiting   → 방 생성 후 대기
drawing   → 날짜 확정 후 지도에서 원 그리기
voting    → 장소 후보 투표 진행
confirmed → 최종 장소 확정
idle      → 전체 초기화 후 다시 시작
```