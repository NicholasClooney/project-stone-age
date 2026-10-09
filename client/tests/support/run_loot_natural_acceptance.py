#!/usr/bin/env python3
"""Test-only frozen invocation; real engine/preflight remain UNRUN for r3.

File-backed stdout+stderr / Godot log, first-error SIGKILL, then unconditional
post/inventory follow the previously run stop-retry-exact-primary supervisor.
Pure synthetic tests exercise the child supervisor, manifest codec and environment gate.
"""
import argparse
import hashlib
import gzip
import json
import os
from pathlib import Path
import re
import resource
import shutil
import signal
import subprocess
import time

SCRIPT = "res://tests/quest_auto_loot_2760_natural_acceptance_test.gd"
PURPOSE = "reviewed-single-natural-loot-2760-r3"
LOG_LIMIT = 64 * 1024 * 1024  # Each authoritative log; never silently truncate.
MANIFEST_FORMAT = "gzip-json-v1"
MANIFEST_LIMIT = 32 * 1024 * 1024  # Each compressed, complete before/after manifest.
MANIFEST_RAW_LIMIT = 256 * 1024 * 1024  # Bounded decoding; never crop entries.
ENVIRONMENT_RULES = {"GODOT_BIN": "must-be-unset"}
JSON_LIMIT = 16 * 1024 * 1024
TOTAL_LIMIT = 2 * 1024 * 1024 * 1024
FREE_REQUIRED = TOTAL_LIMIT + 256 * 1024 * 1024
PREFLIGHT_LIMIT = 120
POST_LIMIT = 120
MARKER = "NATURAL_ACCEPTANCE_RESULT "
ERROR = re.compile(r"^\s*(?:ERROR:|SCRIPT ERROR:|FAIL(?:ED)?\b:?|Parse Error:)|Parse Error:|Failed to load|Failed loading|Failed[-_]load|ObjectDB instances leaked|resources? still in use|resources? leak", re.I)
CANDIDATES = (
    "client/tests/quest_auto_loot_2760_natural_acceptance_test.gd",
    "client/tests/support/quest_loot_natural_acceptance_backend.gd",
    "client/tests/support/quest_loot_acceptance_evidence.gd",
    "client/tests/support/run_loot_natural_acceptance.py",
    "client/tests/support/loot_acceptance_supervisor_fake_test.py",
)


def fresh(path):
    return not os.path.lexists(path)  # Also rejects a dangling symlink.


def write_json(path, value):
    encoded = (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()
    if len(encoded) > JSON_LIMIT:
        raise ValueError("complete JSON metadata exceeds 16 MiB; no truncation")
    with Path(path).open("xb") as stream:
        stream.write(encoded)
        stream.flush()


def validate_environment(env):
    if "GODOT_BIN" in env:
        raise ValueError("GODOT_BIN must be unset, including empty values; override refused")


def read_manifest(path, deadline=float("inf")):
    path = Path(path)
    if path.stat().st_size > MANIFEST_LIMIT:
        raise ValueError("complete compressed manifest exceeds 32 MiB")
    raw = bytearray()
    with gzip.open(path, "rb") as stream:
        while True:
            if time.monotonic() >= deadline:
                raise TimeoutError("complete manifest read deadline")
            chunk = stream.read(min(65536, MANIFEST_RAW_LIMIT + 1 - len(raw)))
            if not chunk:
                break
            raw.extend(chunk)
            if len(raw) > MANIFEST_RAW_LIMIT:
                raise ValueError("complete decoded manifest exceeds 256 MiB")
    def unique_object(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError("duplicate manifest key")
            value[key] = item
        return value
    return json.loads(raw, object_pairs_hook=unique_object)


def require_manifest_equal(path, expected, deadline=float("inf")):
    if read_manifest(path, deadline) != expected:
        raise ValueError("complete manifest differs: identity/path/realpath/size/SHA or entry set")


def write_manifest(path, value, deadline=float("inf")):
    """Complete lossless JSON in a bounded gzip file; exclusive, no repair/overwrite."""
    path = Path(path)
    if not fresh(path):
        raise FileExistsError("Refuse historical manifest: " + str(path))
    raw_bytes = 0
    class BoundedOutput:
        def __init__(self, stream):
            self.stream = stream
            self.total = 0
        def write(self, data):
            if self.total + len(data) > MANIFEST_LIMIT:
                raise ValueError("complete compressed manifest exceeds 32 MiB")
            self.total += len(data)
            return self.stream.write(data)
        def flush(self):
            self.stream.flush()
    try:
        with path.open("xb") as output:
            with gzip.GzipFile(filename="", mode="wb", fileobj=BoundedOutput(output), mtime=0) as packed:
                buffer = bytearray()
                for token in json.JSONEncoder(ensure_ascii=False, separators=(",", ":")).iterencode(value):
                    if time.monotonic() >= deadline:
                        raise TimeoutError("complete manifest write deadline")
                    encoded = token.encode("utf-8")
                    raw_bytes += len(encoded)
                    if raw_bytes > MANIFEST_RAW_LIMIT:
                        raise ValueError("complete decoded manifest exceeds 256 MiB")
                    buffer.extend(encoded)
                    if len(buffer) >= 65536:
                        packed.write(buffer)
                        buffer.clear()
                packed.write(buffer)
            output.flush()
        require_manifest_equal(path, value, deadline)
        return {"format": MANIFEST_FORMAT, "bytes": path.stat().st_size,
                "raw_bytes": raw_bytes, "sha256": digest(path, deadline)}
    except Exception as error:
        # Keep any partial bytes, and leave an explicit failure beside them.
        try:
            write_json(path.with_name(path.name + ".failure.json"),
                       {"result": "FAIL", "manifest": str(path), "error": repr(error),
                        "raw_bytes_attempted": raw_bytes, "complete": False})
        except Exception:
            pass
        raise


def digest(path, deadline=float("inf")):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        while True:
            if time.monotonic() >= deadline:
                raise TimeoutError("complete content hash deadline")
            chunk = stream.read(1024 * 1024)
            if not chunk:
                return result.hexdigest()
            result.update(chunk)


def files_below(path, deadline):
    seen = set()
    for directory, dirs, files in os.walk(path, followlinks=True):
        if time.monotonic() >= deadline:
            raise TimeoutError("complete dependency inventory deadline")
        real = str(Path(directory).resolve())
        if real in seen:
            dirs[:] = []
            continue
        seen.add(real)
        dirs.sort()
        for name in sorted(files):
            yield Path(directory) / name


def git_identity(root):
    def git(*argv):
        return subprocess.check_output(["git", *argv], cwd=root).decode()
    return {"head": git("rev-parse", "HEAD").strip(),
            "branch": git("branch", "--show-current").strip(),
            "status_porcelain_z": git("status", "--porcelain=v1", "--untracked-files=all", "-z")}


def content_lock(root, engine, deadline):
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).split(b"\0")
    paths = {root / os.fsdecode(name) for name in tracked if name}
    paths.update(files_below(root / "client", deadline))
    paths.update((engine, root / "build/fast_hunt"))
    result = {}
    for path in sorted(paths, key=str):
        if not path.is_file():
            raise ValueError("Missing complete-lock dependency: " + str(path))
        result[str(path)] = {"realpath": str(path.resolve()), "bytes": path.stat().st_size,
                             "sha256": digest(path, deadline)}
    return {"identity": git_identity(root), "files": result}


def inventory(root, deadline):
    if not os.path.lexists(root):
        return {"exists": False, "files": {}, "bytes": 0}
    if Path(root).is_symlink():
        raise ValueError("user evidence root became a symlink")
    entries = {}
    total = 0
    for path in files_below(root, deadline):
        if path.is_symlink():
            raise ValueError("user evidence contains an unowned symlink")
        size = path.stat().st_size
        total += size
        entries[str(path.relative_to(root))] = {"bytes": size, "sha256": digest(path, deadline)}
    return {"exists": True, "files": entries, "bytes": total}


def scan_log(path):
    # Final full scan includes incomplete last lines and resource-leak tails.
    if not path.is_file() or path.is_symlink():
        raise ValueError("missing/unowned authoritative log: " + str(path))
    if path.stat().st_size > LOG_LIMIT:
        raise ValueError("authoritative log exceeds 64 MiB")
    errors, summaries, invalid = [], [], []
    error_count = summary_count = invalid_count = 0
    with path.open(encoding="utf-8", errors="strict") as stream:
        for number, line in enumerate(stream, 1):
            if ERROR.search(line):
                error_count += 1
                if len(errors) < 8:
                    errors.append({"line": number, "text": line.rstrip()[:512]})
            if MARKER.strip() in line:
                summary_count += 1
                if len(line.encode()) > 16384:
                    invalid_count += 1
                    if len(invalid) < 8:
                        invalid.append({"line": number, "reason": "summary exceeds 16 KiB"})
                    continue
                text = line.lstrip()
                if not text.startswith(MARKER):
                    invalid_count += 1
                    if len(invalid) < 8:
                        invalid.append({"line": number, "reason": "malformed marker"})
                    continue
                try:
                    summary = json.loads(text[len(MARKER):])
                    if not isinstance(summary, dict):
                        raise ValueError("summary is not an object")
                    if len(summaries) < 2:
                        summaries.append(summary)
                except (ValueError, TypeError) as error:
                    invalid_count += 1
                    if len(invalid) < 8:
                        invalid.append({"line": number, "reason": str(error)})
    return {"sha256": digest(path), "bytes": path.stat().st_size, "errors": errors,
            "summaries": summaries, "invalid_summaries": invalid, "summary_count": summary_count,
            "error_count": error_count, "invalid_count": invalid_count}


class ErrorMonitor:
    """Incrementally scans both files during execution; final scan is independent."""
    def __init__(self, paths):
        self.paths = paths
        self.offsets = {path: 0 for path in paths}
        self.tails = {path: b"" for path in paths}

    def poll(self):
        for path in self.paths:
            if not os.path.lexists(path):
                continue  # Engine may not have opened its log yet.
            if path.is_symlink() or not path.is_file():
                return "unowned-log"
            size = path.stat().st_size
            if size > LOG_LIMIT or size < self.offsets[path]:
                return "log-size-or-rewind"
            with path.open("rb") as stream:
                stream.seek(self.offsets[path])
                data = stream.read()
            self.offsets[path] = size
            combined = self.tails[path] + data
            lines = combined.split(b"\n")
            self.tails[path] = lines.pop()
            if len(self.tails[path]) > JSON_LIMIT:
                return "log-line-overflow"
            for line in lines:
                if ERROR.search(line.decode("utf-8", errors="replace")):
                    return "first-error:" + str(path)
        return ""


def adjudicate(mode, child_exit, logs, problems, post):
    if problems or any(row["errors"] or row["invalid_summaries"] for row in logs.values()):
        return "FAIL"
    if len(logs) != 2 or not all(row.get("status") == "COMPLETE" for row in post.values()):
        return "FAIL"
    if not post["source"]["value"].get("unchanged", False):
        return "FAIL"
    if mode == "check-only":
        return "PASS" if child_exit == 0 and all(not row["summaries"] for row in logs.values()) else "FAIL"
    if any(row["summary_count"] != 1 or len(row["summaries"]) != 1 for row in logs.values()):
        return "FAIL"
    first, second = [row["summaries"][0] for row in logs.values()]
    if first != second:
        return "FAIL"
    if first.get("result") == "PASS":
        return "PASS" if child_exit == 0 and first.get("target") == "PROVEN" and first.get("p3") == "PROVEN" and type(first.get("received_2760")) is int and first["received_2760"] > 0 else "FAIL"
    if first.get("result") == "UNPROVEN":
        return "UNPROVEN" if child_exit == 3 and (first.get("target") == "TARGET_UNPROVEN" or first.get("p3") == "P3_NATURAL_UNPROVEN") else "FAIL"
    return "FAIL"


def execute_child(argv, cwd, env, evidence, mode, post_source, user_inventory,
                  popen=subprocess.Popen, clock=time.monotonic, sleep=time.sleep,
                  kill=lambda proc: os.killpg(proc.pid, signal.SIGKILL)):
    """No preflight here. Injection seams are solely for pure FakePopen validation."""
    paths = [evidence / "stdout.log", evidence / "godot.log"]
    for path in paths + [evidence / "result.json"]:
        if not fresh(path):
            raise FileExistsError("Refuse historical artifact: " + str(path))
    limit = 30 if mode == "check-only" else 2400
    start = clock()
    deadline = start + limit
    child = None
    child_exit = None
    child_end = None
    problems = []
    logs = {}
    post = {}
    stop_reason = ""
    cpu_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    try:
        validate_environment(env)
        with paths[0].open("xb") as output:
            child = popen(argv, cwd=cwd, env=env, stdout=output,
                          stderr=subprocess.STDOUT, start_new_session=True)
            monitor = ErrorMonitor(paths)
            while child.poll() is None:
                stop_reason = monitor.poll()
                if not stop_reason and clock() >= deadline:
                    stop_reason = "engine-hard-timeout"
                if stop_reason:
                    kill(child)
                    break
                sleep(0.025)
            child_exit = child.wait()
        child_end = clock()
    except Exception as error:
        problems.append("execution:" + repr(error))
    finally:
        if child is not None:
            try:
                if child.poll() is None:
                    kill(child)
                child_exit = child.wait()
            except Exception as error:
                problems.append("child-retirement:" + repr(error))
        child_end = child_end if child_end is not None else clock()
        cpu_after = resource.getrusage(resource.RUSAGE_CHILDREN) # Before post-source git subprocesses.
        # Each action is independent: malformed JSON, missing/failed log reads,
        # source failure or inventory failure cannot skip another post action.
        for path in paths:
            try:
                logs[path.name] = scan_log(path)
            except Exception as error:
                problems.append(path.name + ":" + repr(error))
        post_deadline = min(deadline, clock() + POST_LIMIT) if mode == "run" else clock() + POST_LIMIT
        for label, hook in (("source", post_source), ("inventory", user_inventory)):
            began = clock()
            try:
                value = hook(post_deadline)
                post[label] = {"status": "COMPLETE", "value": value, "wall_seconds": clock() - began}
            except Exception as error:
                post[label] = {"status": "UNKNOWN", "error": repr(error), "wall_seconds": clock() - began}
        if stop_reason:
            problems.append(stop_reason)
        if mode == "run" and clock() >= deadline:
            problems.append("runtime-outer-40min-including-post-exhausted")
    outcome = adjudicate(mode, child_exit, logs, problems, post)
    if "timeout" in stop_reason or any("TimeoutError" in row.get("error", "") for row in post.values()):
        outcome = "UNCOMPLETE"
    outer_exit = 0 if outcome == "PASS" else 3 if outcome == "UNPROVEN" else 1
    result = {"mode": mode, "result": outcome, "child_exit": child_exit,
              "outer_exit": outer_exit, "problems": problems, "logs": logs, "post": post,
              "child_wall_seconds": child_end - start, "runtime_outer_wall_seconds": clock() - start,
              "engine_limit_seconds": limit, "post_limit_seconds": POST_LIMIT,
              "child_user_cpu_seconds": cpu_after.ru_utime - cpu_before.ru_utime,
              "child_system_cpu_seconds": cpu_after.ru_stime - cpu_before.ru_stime,
              "capture": "file-backed stdout+stderr and independent full Godot log, both scanned after wait",
              "no_retry": True, "no_rescue_save": True}
    try:
        write_json(evidence / "result.json", result)
    except Exception as error:
        result.update({"result": "FAIL", "outer_exit": 1, "result_artifact_status": "UNKNOWN",
                       "result_write_error": repr(error)})
        # Never overwrite/repair a partial result; post-source/inventory already ran.
        try:
            write_json(evidence / "finalize-failure.json", {"result": "FAIL", "error": repr(error),
                       "post_status": {key: row["status"] for key, row in post.items()}})
        except Exception:
            pass
    return result


def nearest_existing(path):
    while not path.exists():
        path = path.parent
    return path


def expected_argv(engine, root, evidence, mode):
    argv = [str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(root / "client"),
            "--log-file", str(evidence / "godot.log")]
    if mode == "check-only":
        argv.append("--check-only")
    return argv + ["--script", SCRIPT]


def validate_freeze(frozen, root, engine, evidence, before, argv, user_name):
    expected = {"purpose": PURPOSE, "suite": SCRIPT, "root": str(root),
                "engine": str(engine), "evidence": str(evidence), "argv": argv,
                "user_name": user_name, "identity": before["identity"],
                "content_lock_format": MANIFEST_FORMAT, "environment_rules": ENVIRONMENT_RULES}
    for key, value in expected.items():
        if frozen.get(key) != value:
            raise ValueError("Frozen input mismatch: " + key)
    actual = {name: digest(root / name) for name in CANDIDATES}
    if frozen.get("candidate_sha256") != actual:
        raise ValueError("Exact candidate SHA set differs from reviewed freeze")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--freeze", required=True)
    parser.add_argument("--freeze-sha256", required=True)
    args = parser.parse_args()
    freeze_path = Path(args.freeze).resolve(strict=True)
    if digest(freeze_path) != args.freeze_sha256:
        raise ValueError("Freeze bytes do not match reviewed SHA")
    frozen = json.loads(freeze_path.read_text())
    if frozen.get("mode") not in ("check-only", "run"):
        raise ValueError("Explicit frozen mode required")
    mode = frozen["mode"]
    root = Path(__file__).resolve().parents[3]
    evidence = Path(frozen["evidence"])
    if not evidence.is_absolute() or root == evidence.resolve() or root in evidence.resolve().parents or not fresh(evidence):
        raise ValueError("Fresh absolute evidence directory outside checkout required")
    engine = Path(frozen["engine"]).resolve(strict=True)
    user_name = frozen["user_name"]
    prefix = "Godot/app_userdata/Stone Age tests/"
    if not user_name.startswith(prefix) or ".." in Path(user_name).parts or Path(user_name).is_absolute():
        raise ValueError("Dedicated relative test-user namespace required")
    data_root = Path.home() / "Library/Application Support" if os.uname().sysname == "Darwin" else Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    user_dir = data_root / user_name
    if not fresh(user_dir):
        raise FileExistsError("Test user path already exists, including dangling symlink")
    for destination in [evidence.parent, user_dir.parent]:
        if shutil.disk_usage(nearest_existing(destination)).free < FREE_REQUIRED:
            raise ValueError("Need 2 GiB evidence ceiling plus 256 MiB free-space reserve")
    evidence.mkdir(parents=True, exist_ok=False)
    pre_started = time.monotonic()
    deadline = pre_started + PREFLIGHT_LIMIT
    env = os.environ.copy()
    try:
        validate_environment(env)
        # Preflight is separately measured, never charged against the engine's 30s.
        before = content_lock(root, engine, deadline)
        lock_path = Path(frozen["content_lock_path"]).resolve(strict=True)
        if frozen.get("content_lock_format") != MANIFEST_FORMAT or digest(lock_path, deadline) != frozen["content_lock_sha256"]:
            raise ValueError("Complete source/data/cache/engine/helper lock format/SHA differs from reviewed freeze")
        require_manifest_equal(lock_path, before, deadline)
        argv = expected_argv(engine, root, evidence, mode)
        validate_freeze(frozen, root, engine, evidence, before, argv, user_name)
        if mode == "run":
            checked = Path(frozen["checked_result_path"]).resolve(strict=True)
            if digest(checked, deadline) != frozen["checked_result_sha256"]:
                raise ValueError("Checked result bytes changed")
            result = json.loads(checked.read_text())
            checked_invocation = json.loads((checked.parent / "invocation.json").read_text())
            if result.get("mode") != "check-only" or result.get("result") != "PASS" or checked_invocation.get("candidate_sha256") != frozen["candidate_sha256"] or checked_invocation.get("content_lock_sha256") != frozen["content_lock_sha256"]:
                raise ValueError("Successful exact-input check-only required")
        before_manifest = write_manifest(evidence / "contents-before.json.gz", before, deadline)
        write_json(evidence / "invocation.json", {**frozen, "freeze_sha256": args.freeze_sha256,
                   "stored_before_manifest": before_manifest,
                   "preflight_wall_seconds": time.monotonic() - pre_started, "preflight_limit_seconds": PREFLIGHT_LIMIT})
    except Exception as error:
        write_json(evidence / "preflight-failure.json", {"error": repr(error), "engine_started": False,
                   "preflight_wall_seconds": time.monotonic() - pre_started, "no_retry": True})
        return 1
    env["STONE_AGE_TEST_USER_DIR"] = user_name
    for name in ("STONE_AGE_FOREGROUND_TEST", "STONE_AGE_PROOF_DIR"):
        env.pop(name, None)

    def post_source(post_deadline):
        after = content_lock(root, engine, post_deadline)
        stored = write_manifest(evidence / "contents-after.json.gz", after, post_deadline)
        require_manifest_equal(evidence / "contents-before.json.gz", before, post_deadline)
        return {"unchanged": after == before, "content_lock_sha256": stored["sha256"], "manifest": stored}

    def post_inventory(post_deadline):
        user = inventory(user_dir, post_deadline)
        outputs = inventory(evidence, post_deadline)
        if user["bytes"] + outputs["bytes"] > TOTAL_LIMIT - 2 * JSON_LIMIT:
            raise ValueError("Complete evidence exceeds 2 GiB less final metadata reserve")
        write_json(evidence / "user-inventory.json", user)
        return {"user": user, "output_bytes": outputs["bytes"], "ceiling_bytes": TOTAL_LIMIT}

    result = execute_child(argv, root, env, evidence, mode, post_source, post_inventory)
    return result["outer_exit"]


if __name__ == "__main__":
    raise SystemExit(main())
