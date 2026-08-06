import os
import sqlite3

from flask import Flask, request

app = Flask(__name__)

# Read at import, the way configuration usually is. A clean checkout has no
# DATABASE_PATH, so the process exits before it can serve anything, which is
# what makes this fixture exercise the fallback rather than the boot.
DATABASE_PATH = os.environ["DATABASE_PATH"]


@app.route("/search")
def search():
    term = request.args.get("q")
    conn = sqlite3.connect(DATABASE_PATH)
    return str(conn.execute("SELECT * FROM items WHERE name = '" + term + "'").fetchall())
