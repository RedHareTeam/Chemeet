# Chemeet

## 프로젝트 구조

```bash
lib/
├── main.dart                  # 앱 시작점, Firebase/.env 초기화, 첫 화면 분기
├── firebase_options.dart      # Firebase 플랫폼별 설정
├── app_theme.dart             # 공통 색상/텍스트/컴포넌트 테마 정의
│
├── screens/
│   ├── auth_screen.dart           # 로그인/회원가입 진입 화면
│   ├── room_list_screen.dart      # 내 방 목록 조회, 방 생성/초대 코드 입장
│   ├── room_home_screen.dart      # 방 홈, 친밀도/키워드/참여자/약속 상태 표시
│   ├── upload_screen.dart         # 대화 txt 업로드 및 분석 요청 시작
│   ├── analyzing_screen.dart      # 업로드한 대화 분석 진행 화면
│   ├── date_setting_screen.dart   # 약속 날짜/시간 설정
│   ├── map_screen.dart            # 카카오맵에서 원 그리기 및 장소 검색 요청
│   └── place_screen.dart          # 후보 장소 투표 및 최종 장소 확정
│
├── services/
│   ├── auth_service.dart          # Firebase Auth 및 사용자 정보 처리
│   ├── room_service.dart          # 방 생성/입장/조회/히스토리 저장/초기화
│   ├── circle_service.dart        # 원 좌표 저장, 메시지 저장, 장소 저장, 상태 변경
│   ├── vote_service.dart          # 장소 투표/좋아요/싫어요 처리
│   └── place_service.dart         # 지도 기반 주변 장소 검색
│
└── widgets/
    └── kakao_map_webview.dart     # 카카오맵 웹뷰 래퍼, 원 그리기/표시 담당
```

## DB 구조 (Firestore)

### 1. `users` 컬렉션

사용자 기본 정보와 사용자가 참여 중인 방 목록 저장

```bash
users/{userId}
├── userName: string
└── rooms: [roomId1, roomId2, ...]
```

### 2. `rooms` 컬렉션

방의 메인 상태와 약속 진행 정보 저장

```bash
rooms/{roomId}
├── createdBy: string                 # 방 생성자 uid
├── members: [userId1, userId2, ...]  # 참여자 uid 목록
├── memberNames: { userId: userName } # uid-이름 매핑
├── roomTitle: string                 # 방 제목
├── inviteCode: string                # 초대 코드
├── maxMembers: number                # 최대 인원
├── status: string                    # waiting / drawing / voting / confirmed / idle
├── intimacyScore: number             # 대화 분석 기반 친밀도 점수
├── keywords: [string, ...]           # 대화 분석 키워드
├── partnerName: string               # 상대 이름
├── appointmentDate: timestamp        # 약속 날짜/시간
├── places: [Map, Map, ...]           # 후보 장소 리스트
├── confirmedPlace: Map               # 최종 확정 장소
└── createdAt: timestamp              # 생성 시간
```

### 3. `rooms/{roomId}/circles`

지도에서 사용자가 그린 원 정보 저장

```bash
rooms/{roomId}/circles/{userId}
├── userId: string
├── userName: string
├── lat: number
├── lng: number
├── radius: number
└── updatedAt: timestamp
```

### 4. `rooms/{roomId}/messages`

원 그리기 과정에서 생성되는 안내/상태 메시지 저장

```bash
rooms/{roomId}/messages/{messageId}
├── userId: string
├── userName: string
├── message: string
└── createdAt: timestamp
```

### 5. `rooms/{roomId}/votes`

장소 투표 및 반응 상태를 저장

```bash
rooms/{roomId}/votes/{userId}
├── userId: string
├── selectedPlaceId: string
├── likes: [placeId, ...]
└── dislikes: [placeId, ...]
```

### 6. `rooms/{roomId}/history`

최종 확정된 약속 결과를 히스토리로 저장

```bash
rooms/{roomId}/history/{historyId}
├── confirmedPlace: Map
├── members: [userId1, userId2, ...]
├── appointmentDate: timestamp
└── date: timestamp
```

## 각 파일 역할

### `main.dart`
- `.env` 로드
- Firebase 초기화
- 로그인 상태에 따라 첫 화면 분기

### `room_list_screen.dart`
- 내가 속한 방 목록 실시간 조회
- 방 생성 화면 이동
- 초대 코드 입력 후 방 입장
- 방 상태에 따라 방 홈으로 이동

### `upload_screen.dart`
- 방 제목 입력
- 최대 인원 선택
- txt 파일 업로드
- 분석 화면으로 이동

### `analyzing_screen.dart`
- 업로드한 대화 내용을 분석 요청
- 친밀도, 키워드, 상대 이름 등 분석 결과 생성
- 결과를 방 데이터에 반영

### `room_home_screen.dart`
- 방의 핵심 요약 화면
- 참여자 현황 표시
- 친밀도 점수, 키워드, 다음 약속 히스토리 표시
- 현재 `status`에 따라 날짜 설정 / 지도 보기 / 투표 화면 이동

### `date_setting_screen.dart`
- 날짜 선택기와 시간 선택기 제공
- 선택 완료 시 `appointmentDate` 저장
- 방 상태를 `drawing`으로 바꾸고 지도 화면으로 이동

### `map_screen.dart`
- 카카오맵 표시
- 사용자별 원 그리기 및 저장
- 상대 원 실시간 반영
- 메시지 실시간 반영
- 주변 장소 검색 후 후보 장소 저장
- 상태가 `voting`이면 투표 화면으로 이동

### `place_screen.dart`
- 후보 장소 목록 표시
- 장소별 투표/좋아요/싫어요 처리
- 전원 투표 완료 시 최종 장소 확정
- 다시 그리기, 전체 초기화, 확정 다이얼로그 처리

### `room_service.dart`
- 방 생성
- 초대 코드 입장
- 방 단건 조회/실시간 조회
- 확정 후 히스토리 저장
- 서브컬렉션(circles/messages/votes) 정리

### `circle_service.dart`
- 원 좌표 저장/조회
- 지도 메시지 저장/조회
- 후보 장소 저장
- 방 상태 변경(drawing/voting/confirmed 등)

### `vote_service.dart`
- 장소 선택 저장
- 좋아요/싫어요 토글
- 투표 결과 실시간 조회

### `place_service.dart`
- 선택한 좌표 기준으로 주변 장소 검색
- 지도 단계에서 장소 후보 생성

### `auth_service.dart`
- 로그인/로그아웃
- 현재 사용자 정보 조회
- 유저 문서 생성/관리

### `kakao_map_webview.dart`
- Flutter와 카카오맵 웹뷰 연결
- 원 그리기 모드 제어
- 내 원/상대 원/메시지 시각화

## 상태 흐름

```bash
waiting   -> 방 생성 후 대기 상태
 drawing  -> 날짜 확정 후 지도에서 원 그리기
 voting   -> 장소 후보 조회 후 투표 진행
 confirmed-> 최종 장소 확정
 idle     -> 전체 초기화 후 다시 시작
```
