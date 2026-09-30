import http.server
import json
import socket
import tempfile
import threading
import unittest
import urllib.request
from functools import partial
from pathlib import Path

import serve_web


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url) as reply:
        return reply.read()


class LobbyTest(unittest.TestCase):
    def write_profiles(self, folder: Path, data) -> Path:
        path = folder / "profiles.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def test_profiles_default_title_and_save(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.write_profiles(Path(folder), {"profiles": [{"name": "alice", "port": 8782}, {"name": "bob", "title": "小明", "port": 8783, "save": "user://b.json"}]})
            self.assertEqual(serve_web.load_profiles(path), [
                {"name": "alice", "title": "alice", "port": 8782, "save": "user://alice.json"},
                {"name": "bob", "title": "小明", "port": 8783, "save": "user://b.json"},
            ])

    def test_lobby_marks_online_profiles(self):
        profiles = [{"name": "a", "title": "A", "port": 1, "save": ""}, {"name": "b", "title": "B", "port": 2, "save": ""}]
        rows = serve_web.lobby(profiles, online=lambda port: port == 2)
        self.assertEqual([(r["name"], r["online"]) for r in rows], [("a", False), ("b", True)])
        self.assertNotIn("save", rows[0])

    def test_served_lobby_page_and_json(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "index.html").write_text("game")
            listener = http.server.ThreadingHTTPServer(("127.0.0.1", 0), lambda *a: None)
            open_port = listener.server_address[1]
            with socket.socket() as probe:
                probe.bind(("127.0.0.1", 0))
                closed_port = probe.getsockname()[1]
            path = self.write_profiles(root, {"profiles": [{"name": "up", "port": open_port}, {"name": "down", "port": closed_port}]})
            serve_web.Handler.profiles_path = str(path)
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), partial(serve_web.Handler, directory=folder))
            threading.Thread(target=server.serve_forever, daemon=True).start()
            try:
                base = f"http://127.0.0.1:{server.server_address[1]}"
                page = fetch(base + "/lobby").decode("utf-8")
                self.assertIn("进入", page)
                rows = json.loads(fetch(base + "/lobby.json"))["profiles"]
                self.assertEqual([(r["name"], r["port"], r["online"]) for r in rows], [("up", open_port, True), ("down", closed_port, False)])
                self.assertEqual(fetch(base + "/"), b"game")
            finally:
                server.shutdown()
                server.server_close()
                listener.server_close()
                serve_web.Handler.profiles_path = ""


if __name__ == "__main__":
    unittest.main()
