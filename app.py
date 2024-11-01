from flask import Flask, send_from_directory, jsonify
import os
import json
from flask_cors import CORS
from flask_sock import Sock

app = Flask(__name__, static_folder="./vue-project/dist", static_url_path="")
sock = Sock(app)
CORS(app)


@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def serve_index(path):
    if path != "" and os.path.exists(os.path.join(app.static_folder, path)):
        return send_from_directory(app.static_folder, path)
    return send_from_directory(app.static_folder, "index.html")


@app.route("/data")
def get_data():
    with open("data.json", encoding="utf-8") as f:
        data = json.load(f)
        print(data)
    return jsonify(data)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
