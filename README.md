# Chemeet Backend


## 개발 단계

| 단계 | 작업 | 상태 |
|------|------|------|
| 1 | 환경 구축 | ✅ 완료 |
| 2 | 카카오톡 대화 파싱 | ✅ 완료 |
| 3 | 취향 키워드 추출 | ✅ 완료 |
| 4 | Flask /analyze 엔드포인트 | ✅ 완료 |
| 5 | 친밀도 모듈 | 🔴 진행 중 |
| 6 | 교집합 계산 | ⬜ 미완 |
| 7 | 카카오맵 장소 추천 + /recommend | ⬜ 미완 |
| 8 | 날씨 필터 연동 | ⬜ 미완 |
| 9 | 전체 통합 테스트 | ⬜ 미완 |

---

## 프로젝트 구조

```
chemeet-backend/
├── app.py                    # Flask 서버, API 엔드포인트
├── kakao/
│   ├── kakao_parser.py       # 카카오톡 txt 파싱
│   └── test_*.txt            # 테스트용 시나리오 데이터
├── nlp/
│   └── keyword_extractor.py  # 취향 키워드 추출
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
  "preferred_food": ["한식", "케이크"],
  "avoided_food": ["파스타"],
  "general_preference": ["파스타", "고기"],
  "place": ["카페"],
  "mood": ["분위기", "감성"],
  "search_query": "한식 카페 분위기"
}
```