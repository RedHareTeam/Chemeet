import requests
import os
from dotenv import load_dotenv

load_dotenv()

OPENWEATHER_API_KEY = os.getenv("OPENWEATHER_API_KEY")
OPENWEATHER_URL = "https://api.openweathermap.org/data/2.5/weather"


def get_weather(lat, lng):
    """
    현재 날씨 정보 반환
    반환:
    {
        "condition": "clear/rain/snow/clouds",
        "temp": 18.5,
        "description": "맑음"
    }
    """
    params = {
        "lat": lat,
        "lon": lng,
        "appid": OPENWEATHER_API_KEY,
        "units": "metric",
        "lang": "kr"
    }

    response = requests.get(OPENWEATHER_URL, params=params)

    if response.status_code != 200:
        return {"condition": "unknown", "temp": 0, "description": "날씨 정보 없음"}

    data = response.json()
    weather_id = data["weather"][0]["id"]
    description = data["weather"][0]["description"]
    temp = data["main"]["temp"]

    # 날씨 조건 분류
    if weather_id < 300:
        condition = "thunder"
    elif weather_id < 600:
        condition = "rain"
    elif weather_id < 700:
        condition = "snow"
    elif weather_id == 800:
        condition = "clear"
    else:
        condition = "clouds"

    return {
        "condition": condition,
        "temp": round(temp, 1),
        "description": description
    }


def apply_weather_filter(search_query, weather):
    """
    날씨 조건에 따라 검색 쿼리 보정
    - 비/눈: 실내 위주 추천
    - 맑음: 그대로
    """
    condition = weather.get("condition", "clear")

    # 비나 눈이 오면 실내 장소 우선
    if condition in ["rain", "snow", "thunder"]:
        if "카페" in search_query:
            return search_query  # 카페는 이미 실내
        if "한식당" in search_query or "라멘집" in search_query or "피자집" in search_query:
            return search_query  # 식당도 실내
        return search_query  # 일단 그대로 (추후 실외 장소 제외 로직 추가 가능)

    return search_query


def apply_weather_filter(search_query, weather, search_radius):
    condition = weather.get("condition", "clear")
    
    # 비/눈/천둥 → 반경 줄이기 + 가까운 장소 우선
    if condition in ["rain", "snow", "thunder"]:
        adjusted_radius = min(search_radius, 1500)
        return search_query, adjusted_radius
    
    # 맑음/흐림 → 그대로
    return search_query, search_radius