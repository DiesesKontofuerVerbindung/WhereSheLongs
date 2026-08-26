#!/usr/bin/env python3
"""Local static server for the blink detector (no camera frames are uploaded)."""

from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os

HOST = "127.0.0.1"
PORT = 8765


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        print("[%s] %s" % (self.log_date_time_string(), format % args))


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print("眨眼检测页面: http://%s:%s/" % (HOST, PORT))
    print("按 Ctrl+C 停止服务")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")
        server.server_close()
