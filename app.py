from flask import Flask, request, jsonify
from kakao.kakao_parser import parse_kakao_txt
from nlp.keyword_extractor import extract_keywords, keywords_to_search_query
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

        keywords = extract_keywords(messages)
        search_query = keywords_to_search_query(keywords)

        return jsonify({
            "preferred_food": keywords['preferred_food'],
            "avoided_food": keywords['avoided_food'],
            "general_preference": keywords['general_preference'],
            "place": keywords['place'],
            "mood": keywords['mood'],
            "search_query": search_query
        })

    finally:
        os.remove(tmp_path)


if __name__ == '__main__':
    app.run(debug=True)