#!/usr/bin/env python3
"""Preview the page on localhost, with the HTTP range requests that video seeking needs (the pull and task buttons).
python3 -m http.server does not answer them, so the browser cannot seek; GitHub Pages does.
    usage: tools/serve.py [port]"""
import functools
import http.server
import os
import re
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        self.left = None
        m = re.fullmatch(r"bytes=(\d+)-(\d*)", self.headers.get("Range", ""))
        path = self.translate_path(self.path)
        if not m or not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        start, end = int(m[1]), min(int(m[2] or size - 1), size - 1)
        if start > end:
            self.send_error(416)
            return None
        f = open(path, "rb")
        f.seek(start)
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        self.left = end - start + 1
        return f

    def copyfile(self, src, dst):
        if self.left is None:
            return super().copyfile(src, dst)
        try:
            while self.left > 0:
                b = src.read(min(self.left, 1 << 16))
                if not b:
                    break
                dst.write(b)
                self.left -= len(b)
        except (BrokenPipeError, ConnectionResetError):   # the browser drops range requests it no longer needs
            pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, directory=root))
    print(f"serving {root} at http://127.0.0.1:{port}/")
    server.serve_forever()
