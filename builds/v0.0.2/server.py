#!/usr/bin/env python3
"""
If you run into the errors for "Cross Origin Isolation" and 
"SharedArrayBuffer" when trying to run your exported HTML Godot
game, use this simple server to fix the problem!
Create this file in the same folder as your exported HTML files
and run with `python ./server.py CreateJamGame.html`. Open the
printed URL in a web browser. Use `--port 8080` to change ports.
Running without arguments or with just a port also works.
"""
import argparse
from functools import partial
from http.server import HTTPServer, SimpleHTTPRequestHandler, test
from pathlib import Path
from urllib.parse import quote

class CORSRequestHandler (SimpleHTTPRequestHandler):
    def end_headers (self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        SimpleHTTPRequestHandler.end_headers(self)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", nargs="?", help="HTML file to serve, or a port number")
    parser.add_argument("--port", type=int, help="server port (default: 8000)")
    args = parser.parse_args()

    directory = Path.cwd()
    page = ""
    port = args.port if args.port is not None else 8000
    if args.target:
        if args.target.isdecimal():
            if args.port is None:
                port = int(args.target)
        else:
            target = Path(args.target).resolve()
            if not target.is_file():
                parser.error(f"file not found: {args.target}")
            directory = target.parent
            page = quote(target.name)
    if not 1 <= port <= 65535:
        parser.error("port must be between 1 and 65535")

    print(f"Open http://localhost:{port}/{page}", flush=True)
    handler = partial(CORSRequestHandler, directory=str(directory))
    test(handler, HTTPServer, port=port)
