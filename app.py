from flask import Flask, send_from_directory, jsonify
import os
import json
from flask_cors import CORS
from flask_sock import Sock

app = Flask(__name__, static_folder="./ui/dist", static_url_path="")
sock = Sock(app)
CORS(app)


@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def serve_index(path):
    if path != "" and os.path.exists(os.path.join(app.static_folder, path)):
        return send_from_directory(app.static_folder, path)
    return send_from_directory(app.static_folder, "index.html")


@app.route("/api/lines", methods=["GET"])
def get_lines():
    lines = [
        {
            "geometry": {
                "type": "LineString",
                "coordinates": [[113.5, 34.8], [114.0, 35.0]],
            },
            "properties": {"color": "red", "name": "Line 1"},
        },
        {
            "geometry": {
                "type": "LineString",
                "coordinates": [[112.0, 34.5], [113.0, 35.5]],
            },
            "properties": {"color": "red", "name": "Line 2"},
        },
        {
            "geometry": {
                "type": "LineString",
                "coordinates": [[111.0, 33.8], [112.5, 34.3]],
            },
            "properties": {"color": "red", "name": "Line 3"},
        },
    ]
    return jsonify(lines)


@app.route("/data")
def get_data():
    with open("data.json", encoding="utf-8") as f:
        data = json.load(f)
        print(data)
    return jsonify(data)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
