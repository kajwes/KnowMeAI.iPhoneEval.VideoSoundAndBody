from flask import Flask, request
app = Flask(__name__)
@app.route('/', methods=['POST'])
def result():
    print("received a post request")
    #access the json data (json string is the only element in request.form):
    #for elem in request.form:
    #    print(elem.replace("\\n", "\n")) # raw data
    return "{}"
if __name__ == "__main__":
   app.run(host="192.168.68.53", port=5000, debug=True)
