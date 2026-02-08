#!/usr/bin/env python3
"""Local test server with CORS headers for jsbeeb disc loading."""
import http.server
import sys

PORT = 8080

class CORSHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

print(f"Serving at http://localhost:{PORT}")
print(f"Open http://localhost:{PORT}/index.html to play")
print("Press Ctrl+C to stop")
http.server.HTTPServer(("", PORT), CORSHandler).serve_forever()
