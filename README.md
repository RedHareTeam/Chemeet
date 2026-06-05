<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=ffa5ab&height=200&text=Chemeet&textColor=ffffff&fontSize=60&desc=카카오톡%20대화%20분석%20기반%20모임%20장소%20추천%20앱&descSize=18&descAlignY=75&section=header" width="100%" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Flask-000000?style=flat-square&logo=flask&logoColor=white" />
  <img src="https://img.shields.io/badge/Firebase-FFCA28?style=flat-square&logo=firebase&logoColor=black" />
  <img src="https://img.shields.io/badge/GPT--4o--mini-412991?style=flat-square&logo=openai&logoColor=white" />
</p>

---

## 🎬 시연 영상

<div align="center">
  <a href="https://youtu.be/QrrKvhJ12bc" target="_blank">
    <img width="600" alt="Chemeet 시연영상" src="assets/icon/chemeet.png" />
  </a>
</div>

#### 👉 [시연영상 보러가기](https://youtu.be/QrrKvhJ12bc)

---

## ❤️ 프로젝트 개요

오늘날 약속 장소를 정할 때 위치와 취향 조율에 불필요한 시간이 소비되는 경우가 많다. 기존 서비스는 단순 중간지점 계산에 그쳐 개인 취향이나 관계의 깊이를 반영하지 못한다.

Chemeet은 카카오톡 대화 분석으로 취향과 친밀도를 파악하고, 참여자가 지도에서 설정한 이동 가능 구역의 교집합 안에서 최적 장소를 추천한다. 날씨와 친밀도를 반영해 추천 범위를 조정하고, 멤버 간 투표로 장소를 확정하면 방문 이력이 히트맵으로 축적된다.

---

## 🔑 주요 적용 기술 및 구조

### 개발 환경 및 도구

- **개발 환경**: Windows / macOS, Android, iOS, Web
- **개발 도구**: Android Studio, VS Code, Git
- **개발 언어**: Python, Dart
- **프레임워크**: Flutter 3.x, Flask
- **데이터베이스**: Firebase Firestore

### 주요 개발 기술

- 카카오톡 대화 파싱 및 취향 키워드 자동 추출
- 규칙 기반 친밀도 점수 산출
- 선호 구역 교집합 계산 및 중심 좌표 도출
- 대중교통 접근성 기반 최적 지하철역 탐색
- 교집합 영역 내 장소 검색 및 지도 시각화
- 방문 히스토리 히트맵 시각화

---

## 🛠️ 시스템 구조

<p align="center">
  <img width="500" alt="시스템 구조도" src="assets/icon/system.png" />
</p>

---

## 📱 앱 화면

<p align="center">
  <img width="700" alt="앱 화면" src="assets/icon/screen.png" />
</p>

---

## 💡 핵심 성과 및 독창성

<details>
<summary><b>자동 취향 추출 파이프라인</b></summary>
<div>
  &nbsp;카카오톡 대화 파일 하나로 취향과 친밀도를 한 번에 파악할 수 있다. 별도 설문이나 수동 입력 없이 대화 속 선호를 자동으로 읽어낸다.
</div>
</details>

<details>
<summary><b>교집합 기반 중간지점 알고리즘</b></summary>
<div>
  &nbsp;단순 좌표 평균이 아닌, 각 참여자가 지도에서 이동 가능한 범위를 설정하면 구역이 겹치는 교집합 안에서 대중교통 기준 최적의 중간지점을 찾는다. 참여자 모두가 실제로 갈 수 있는 구역 안에서 중간지점을 잡는다.
</div>
</details>

<details>
<summary><b>날씨 연동 접근성 보정</b></summary>
<div>
  &nbsp;날씨가 좋지 않을 때 탐색 반경을 줄이고 가까운 지하철역 근처로 추천 범위를 좁힌다.
</div>
</details>

<details>
<summary><b>관계 맥락 반영</b></summary>
<div>
  &nbsp;친밀도에 따라 이동 반경과 장소 성격이 달라진다. 친한 친구와의 만남과 업무 미팅은 다른 추천 결과를 제공한다.
</div>
</details>

---

## 👍 기대 효과

- 대화 파일 업로드만으로 취향 분석 및 장소 추천 자동화
- 모임 장소 선정 시 발생하는 시간 낭비와 갈등 해소
- 친구·연인·직장 동료 등 다양한 관계와 상황에 폭넓게 활용 가능
- 예약 플랫폼 연동 및 확장 가능성

---

### 개발 언어
![Python](https://img.shields.io/badge/Python-3670A0?style=for-the-badge&logo=python&logoColor=ffdd54)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)

### 프레임워크 & 도구
![Flask](https://img.shields.io/badge/Flask-000000?style=for-the-badge&logo=flask&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![OpenAI](https://img.shields.io/badge/GPT--4o--mini-412991?style=for-the-badge&logo=openai&logoColor=white)
![Shapely](https://img.shields.io/badge/Shapely-2.0-green?style=for-the-badge)

### API
![KakaoMap](https://img.shields.io/badge/Kakao%20Maps%20API-FFCD00?style=for-the-badge&logo=kakao&logoColor=black)
![ODsay](https://img.shields.io/badge/ODsay%20API-0066CC?style=for-the-badge)
![OpenWeather](https://img.shields.io/badge/OpenWeather%20API-EB6E4B?style=for-the-badge&logo=openweathermap&logoColor=white)

### 개발 도구
![VSCode](https://img.shields.io/badge/VSCode-007ACC?style=for-the-badge&logo=visualstudiocode&logoColor=white)
![AndroidStudio](https://img.shields.io/badge/Android%20Studio-3DDC84?style=for-the-badge&logo=androidstudio&logoColor=white)
![Git](https://img.shields.io/badge/Git-F05032?style=for-the-badge&logo=git&logoColor=white)

---

## 👥 팀

| 역할 | 이름 |
|---|---|
| 백엔드 · AI 모듈 | 양승연 |
| 프론트엔드 · 지도 인터랙션 | 노희서 |

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=ffa5ab&height=100&section=footer" width="100%" />
</p>