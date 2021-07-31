from flask import Flask, request
import json
import os

app = Flask(__name__)
@app.route('/', methods=['POST'])
def result():
    print("received a post request")
    #access the json data (json string is the only element in request.form):
    for elem in request.form:
        json_dict = json.loads(elem.replace("\\n", "\n")) # raw data
        filename = os.path.join("./body_data/", json_dict["timestamp_readable"] + ".json")
        print(filename)
        with open(filename, 'w') as json_file:
            json.dump(json_dict, json_file, indent=4)
    return "{}"
if __name__ == "__main__":
    if not os.path.exists("./body_data/"):
        os.mkdir("./body_data/",  exist_ok=True)
    app.run(host="192.168.68.53", port=5000, debug=True)
