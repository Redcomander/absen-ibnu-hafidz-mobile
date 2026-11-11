"""Local-only API for the isolated Android background sync smoke harness."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.respond({"user": {"id": 901, "name": "Sync smoke"}})

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        print(json.dumps({"path": self.path, "encoding": self.headers.get("Content-Type"),
                          "body": body.decode("utf-8"), "authorization": self.headers.get("Authorization")}), flush=True)
        self.respond({"message": "saved"})

    def respond(self, payload):
        data = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18089), Handler).serve_forever()
