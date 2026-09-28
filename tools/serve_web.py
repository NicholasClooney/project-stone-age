"""Serve the web build (build/web) to browsers on this network.

Compresses the engine, scripts, JSON and packs with gzip once per file
version, marks content-hashed packs immutable and everything else
revalidated, and prints the addresses to open on another device. With
--cert/--key it serves HTTPS, which a browser needs for a secure context.
"""
import argparse
import gzip
import http.server
import os
import socket
import ssl
import subprocess
from functools import partial
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPRESSIBLE = {".wasm", ".js", ".pck", ".json", ".html"}
_cache: dict = {}


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
    }

    def end_headers(self) -> None:
        if "/packs/" in self.path and self.path.endswith(".pck"):
            self.send_header("Cache-Control", "public, max-age=31536000, immutable")
        else:
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def _compressed(self):
        path = Path(self.translate_path(self.path))
        if path.suffix not in COMPRESSIBLE or not path.is_file():
            return None
        if "gzip" not in self.headers.get("Accept-Encoding", ""):
            return None
        stat = path.stat()
        key = (str(path), stat.st_mtime_ns, stat.st_size)
        if key not in _cache:
            _cache[key] = gzip.compress(path.read_bytes(), compresslevel=6)
        return path, _cache[key]

    def _send_compressed(self, head_only: bool) -> bool:
        found = self._compressed()
        if found is None:
            return False
        path, body = found
        self.send_response(200)
        self.send_header("Content-Type", self.guess_type(str(path)))
        self.send_header("Content-Encoding", "gzip")
        # No Content-Length: Godot's web HTTPRequest counts the decoded body the
        # browser hands it against this header and would wait forever for a
        # compressed length. The connection closes after each response instead.
        self.send_header("Connection", "close")
        self.close_connection = True
        self.end_headers()
        if not head_only:
            self.wfile.write(body)
        return True

    def do_GET(self) -> None:
        if not self._send_compressed(False):
            super().do_GET()

    def do_HEAD(self) -> None:
        if not self._send_compressed(True):
            super().do_HEAD()

    def log_message(self, format: str, *args) -> None:
        if os.environ.get("STONE_AGE_WEB_LOG"):
            super().log_message(format, *args)


def lan_addresses() -> list:
    found = []
    for interface in ("en0", "en1"):
        try:
            address = subprocess.run(["ipconfig", "getifaddr", interface], capture_output=True, text=True, timeout=2).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            address = ""
        if address:
            found.append(address)
    return found or [socket.gethostname()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8780)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--dir", default=str(ROOT / "build/web"))
    parser.add_argument("--cert")
    parser.add_argument("--key")
    args = parser.parse_args()
    if not (Path(args.dir) / "index.html").exists():
        raise SystemExit(f"No web build in {args.dir}; run scripts/build-web.sh first.")
    server = http.server.ThreadingHTTPServer((args.bind, args.port), partial(Handler, directory=args.dir))
    scheme = "http"
    if args.cert and args.key:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.cert, args.key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        scheme = "https"
    for address in lan_addresses():
        print(f"Web client: {scheme}://{address}:{args.port}/")
    server.serve_forever()


if __name__ == "__main__":
    main()
