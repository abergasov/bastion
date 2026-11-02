#!/usr/bin/env python3
import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(size) or b"{}")
        if self.path == "/control":
            with self.server.lock:
                self.server.failures = payload.get("failures", 0)
                self.server.attempts = 0
                self.server.messages = []
            self.send_response(204)
            self.end_headers()
            return
        with self.server.lock:
            self.server.attempts += 1
            self.server.messages.append(payload.get("text", ""))
            failed = self.server.failures > 0
            if failed:
                self.server.failures -= 1
        with open(self.server.log_path, "a", encoding="utf-8") as log:
            log.write(json.dumps({"text": payload.get("text", "")}) + "\n")
        self.send_response(502 if failed else 200)
        self.end_headers()

    def do_GET(self):
        with self.server.lock:
            state = {"attempts": self.server.attempts, "messages": self.server.messages}
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(state).encode())

    def log_message(self, *_):
        pass


parser = argparse.ArgumentParser()
parser.add_argument("--bind", default="127.0.0.1")
parser.add_argument("--port", type=int, required=True)
parser.add_argument("--log", required=True)
args = parser.parse_args()
server = HTTPServer((args.bind, args.port), Handler)
server.log_path = args.log
server.lock = threading.Lock()
server.failures = 0
server.attempts = 0
server.messages = []
server.serve_forever()
