from flask import Flask, request, jsonify
from kakao.kakao_parser import parse_kakao_txt
from nlp.openai_analyzer import analyze_with_openai
from nlp.rule_based import calculate_intimacy_score, get_intimacy_label, calculate_radius_expansion
import os
import tempfile

app = Flask(__name__)

@app.route('/')
def index():
    return jsonify({"status": "Chemeet API 서버 실행 중"})


@app.route('/analyze', methods=['POST'])
def analyze():
    if 'file' not in request.files:
        return jsonify({"error": "파일이 없습니다"}), 400

    file = request.files['file']

    if file.filename == '':
        return jsonify({"error": "파일명이 없습니다"}), 400

    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='wb') as tmp:
        file.save(tmp)
        tmp_path = tmp.name

    try:
        messages = parse_kakao_txt(tmp_path)

        if not messages:
            return jsonify({"error": "파싱된 메시지가 없습니다"}), 400
        # OpenAI 취향 분석
        keywords = analyze_with_openai(messages)

        # 친밀도 분석용
        INTIMACY_MAX_MESSAGES = 100
        messages_for_intimacy = messages[-INTIMACY_MAX_MESSAGES:]

        intimacy_score = calculate_intimacy_score(messages_for_intimacy)
        intimacy_label = get_intimacy_label(intimacy_score)
        radius_expansion = calculate_radius_expansion(intimacy_score)

        return jsonify({
            "senders": keywords['senders'],
            "intimacy_score": intimacy_score,
            "intimacy_label": intimacy_label,
            "radius_expansion": radius_expansion,
            "purpose": keywords['purpose'],
            "preferred_food": keywords['preferred_food'],
            "avoided_food": keywords['avoided_food'],
            "place_type": keywords['place_type'],
            "secondary_place_type": keywords['secondary_place_type'],
            "mood": keywords['mood'],
            "search_query": keywords['search_query']
        })

    finally:
        os.remove(tmp_path)


if __name__ == '__main__':
    app.run(debug=True)