"""Serve the web build (build/web) to browsers on this network.

Compresses the engine, scripts, JSON and packs with gzip once per file
version, marks content-hashed packs immutable and everything else
revalidated, and prints the addresses to open on another device. With
--cert/--key it serves HTTPS, which a browser needs for a secure context.
With --profiles (scripts/profiles.sh) it also serves the LAN lobby at /lobby:
every profile on this computer, whether its server is online, and a link
that opens the web client on it (docs/development/lan-profiles.md).
"""
import argparse
import errno
import gzip
import http.server
import json
import os
import socket
import ssl
import subprocess
import sys
from functools import partial
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPRESSIBLE = {".wasm", ".js", ".pck", ".json", ".html"}
LOBBY_PAGE = ROOT / "web" / "lobby.html"
_cache: dict = {}


def load_profiles(path) -> list:
    """The profiles of a profiles.json: [{name, title, port, save}]."""
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    result = []
    for entry in data.get("profiles", []):
        name = str(entry["name"])
        result.append({"name": name, "title": str(entry.get("title") or name), "port": int(entry["port"]),
                       "save": str(entry.get("save") or f"user://{name}.json")})
    return result


def port_open(port: int) -> bool:
    """Whether a server on this computer listens on the port. It tries to bind
    the port rather than connect: a probe connection would make the backend
    log a failed TLS handshake every few seconds."""
    for host in ("0.0.0.0", "127.0.0.1"):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            try:
                probe.bind((host, port))
            except OSError as error:
                if error.errno == errno.EADDRINUSE:
                    return True
    return False


def lobby(profiles: list, online=port_open) -> list:
    """What the lobby page lists: name, title, port and whether it answers."""
    return [{"name": p["name"], "title": p["title"], "port": p["port"], "online": bool(online(p["port"]))} for p in profiles]


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

    profiles_path = ""

    def _send_bytes(self, body: bytes, content_type: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _lobby(self) -> bool:
        if not self.profiles_path:
            return False
        path = self.path.split("?", 1)[0]
        if path in ("/lobby", "/lobby/", "/lobby.html"):
            self._send_bytes(LOBBY_PAGE.read_bytes(), "text/html; charset=utf-8")
            return True
        if path == "/lobby.json":
            try:
                body = json.dumps({"profiles": lobby(load_profiles(self.profiles_path))}, ensure_ascii=False)
            except (OSError, ValueError, KeyError) as error:
                body = json.dumps({"profiles": [], "error": str(error)}, ensure_ascii=False)
            self._send_bytes(body.encode("utf-8"), "application/json; charset=utf-8")
            return True
        return False

    def do_GET(self) -> None:
        if self._lobby():
            return
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
    if sys.platform == "darwin":
        for interface in ("en0", "en1"):
            try:
                address = subprocess.run(["ipconfig", "getifaddr", interface], capture_output=True, text=True, timeout=2).stdout.strip()
            except (OSError, subprocess.TimeoutExpired):
                address = ""
            if address:
                found.append(address)
    else:
        # The address of the default route; connecting a UDP socket sends nothing.
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                probe.connect(("192.0.2.1", 9))
                found.append(probe.getsockname()[0])
        except OSError:
            pass
    return found or [socket.gethostname()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8780)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--dir", default=str(ROOT / "build/web"))
    parser.add_argument("--cert")
    parser.add_argument("--key")
    parser.add_argument("--profiles", help="profiles.json: also serve the LAN lobby at /lobby")
    args = parser.parse_args()
    if not (Path(args.dir) / "index.html").exists():
        raise SystemExit(f"No web build in {args.dir}; run scripts/build-web.sh first.")
    if args.profiles:
        Handler.profiles_path = str(Path(args.profiles).resolve())
    server = http.server.ThreadingHTTPServer((args.bind, args.port), partial(Handler, directory=args.dir))
    scheme = "http"
    if args.cert and args.key:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.cert, args.key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        scheme = "https"
    for address in lan_addresses():
        print(f"Web client: {scheme}://{address}:{args.port}/")
        if args.profiles:
            print(f"Lobby: {scheme}://{address}:{args.port}/lobby")
    server.serve_forever()


if __name__ == "__main__":
    main()
