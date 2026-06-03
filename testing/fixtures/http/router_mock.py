#!/usr/bin/env python3

import argparse
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class RouterMockHandler(BaseHTTPRequestHandler):
    def _write_json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _write_raw(self, text, status=200, content_type="application/json"):
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _store(self, name, content):
        path = os.path.join(self.server.output_dir, name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(content)

    def _increment(self, counter_name):
        path = os.path.join(self.server.output_dir, counter_name)
        value = 0
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as handle:
                raw = handle.read().strip()
                if raw.isdigit():
                    value = int(raw)
        value += 1
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(str(value))

    def _env_status(self, name, default=200):
        raw = os.getenv(name, str(default)).strip()
        try:
            value = int(raw)
        except ValueError:
            return default
        if value < 100 or value > 599:
            return default
        return value

    def do_GET(self):
        self._store("last_get_path.txt", self.path)
        if self.path.startswith("/cgi-bin/router-channel-recommend"):
            self._increment("recommend.count")
            status = self._env_status("ROUTER_MOCK_RECOMMEND_STATUS", 200)
            mode = os.getenv("ROUTER_MOCK_RECOMMEND_MODE", "ok").strip().lower()
            if mode == "invalid_json":
                self._write_raw('{"status": "ok"', status=status)
            elif mode == "status_error":
                self._write_json({"status": "error", "reason": "fixture_recommend_error"}, status=status)
            elif mode == "missing_fields":
                self._write_json({"status": "ok", "band": "2g"}, status=status)
            else:
                self._write_json(
                    {
                        "status": "ok",
                        "band": "2g",
                        "current_channel": 1,
                        "recommended_channel": 6,
                        "score_gap": 22,
                        "confidence": "high",
                        "rf_model": "fixture_rf_v1",
                    },
                    status=status,
                )
            return

        self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length).decode("utf-8") if length > 0 else ""
        headers_dump = "\n".join(f"{k}: {v}" for k, v in self.headers.items())

        if self.path == "/cgi-bin/router-event":
            self._increment("event.count")
            self._store("router_event.body.json", body)
            self._store("router_event.headers.txt", headers_dump)
            status = self._env_status("ROUTER_MOCK_EVENT_STATUS", 200)
            mode = os.getenv("ROUTER_MOCK_EVENT_MODE", "ok").strip().lower()
            if mode == "invalid_json":
                self._write_raw('{"status":"ok"', status=status)
            elif mode == "status_error":
                self._write_json({"status": "error", "reason": "fixture_event_error"}, status=status)
            else:
                self._write_json({"status": "ok"}, status=status)
            return

        if self.path == "/cgi-bin/router-channel-apply":
            self._increment("apply.count")
            self._store("router_apply.body.json", body)
            self._store("router_apply.headers.txt", headers_dump)
            status = self._env_status("ROUTER_MOCK_APPLY_STATUS", 200)
            mode = os.getenv("ROUTER_MOCK_APPLY_MODE", "ok").strip().lower()
            if mode == "invalid_json":
                self._write_raw('{"status":"ok"', status=status)
            elif mode == "status_error":
                self._write_json({"status": "error", "reason": "fixture_apply_error"}, status=status)
            else:
                self._write_json({"status": "ok", "reason": "applied"}, status=status)
            return

        self.send_error(404)

    def log_message(self, format, *args):
        return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)
    server = ThreadingHTTPServer((args.host, 0), RouterMockHandler)
    server.output_dir = args.output_dir

    with open(args.port_file, "w", encoding="utf-8") as handle:
        handle.write(str(server.server_port))

    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()