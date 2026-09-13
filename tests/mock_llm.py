#!/usr/bin/env python3
"""Mock OpenAI-compatible (llama.cpp-style) SSE server for the zoracle e2e test.

Scripted behaviour (per request count):
  request #1  -> streams reasoning + a native tool call (time, spec "now")
  request #2+ -> streams a final plain-text answer

Every request body is recorded as request_<n>.json next to the port file so
tests can assert on what was actually sent (e.g. the "tools" key, tool
results fed back as role:"tool" messages).
"""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer

STATE_DIR = os.environ.get("MOCK_STATE_DIR", ".")


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"  # close after each response; curl reads to EOF

    def log_message(self, *_):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length)

        count = 0
        cnt_path = os.path.join(STATE_DIR, "request_count")
        if os.path.exists(cnt_path):
            with open(cnt_path) as f:
                count = int(f.read().strip() or "0")
        with open(os.path.join(STATE_DIR, "request_%d.json" % count), "wb") as f:
            f.write(body)
        with open(cnt_path, "w") as f:
            f.write(str(count + 1))

        if count == 0:
            chunks = [
                {"choices": [{"index": 0,
                              "delta": {"role": "assistant",
                                        "reasoning_content": "I need the current time. "},
                              "finish_reason": None}]},
                {"choices": [{"index": 0,
                              "delta": {"tool_calls": [
                                  {"index": 0, "id": "call_e2e_1",
                                   "type": "function",
                                   "function": {"name": "time", "arguments": ""}}]},
                              "finish_reason": None}]},
                {"choices": [{"index": 0,
                              "delta": {"tool_calls": [
                                  {"index": 0,
                                   "function": {"arguments": "{\"spec\""}}]},
                              "finish_reason": None}]},
                {"choices": [{"index": 0,
                              "delta": {"tool_calls": [
                                  {"index": 0,
                                   "function": {"arguments": ":\"now\"}"}}]},
                              "finish_reason": None}]},
                {"choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]},
            ]
        else:
            chunks = [
                {"choices": [{"index": 0,
                              "delta": {"content": "Final answer: the tool result is above."},
                              "finish_reason": None}]},
                {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]},
            ]

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for chunk in chunks:
            self.wfile.write(b"data: " + json.dumps(chunk).encode() + b"\n\n")
            self.wfile.flush()
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


def main():
    port = free_port()
    with open(os.path.join(STATE_DIR, "port"), "w") as f:
        f.write(str(port))
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
