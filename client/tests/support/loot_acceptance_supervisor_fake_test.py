#!/usr/bin/env python3
"""Pure FakePopen tests. No main(), preflight(), content_lock(), engine or real cache.
Run only this synthetic harness with python3 -B after explicit authorization.
"""
import sys
sys.dont_write_bytecode = True
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("loot_supervisor", Path(__file__).with_name("run_loot_natural_acceptance.py"))
S = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(S)
PASS = {"result": "PASS", "target": "PROVEN", "p3": "PROVEN", "received_2760": 1}
UNPROVEN = {"result": "UNPROVEN", "target": "TARGET_UNPROVEN", "p3": "PROVEN", "received_2760": 0}


def line(value):
    return S.MARKER + json.dumps(value) + "\n"


class FakePopen:
    """Writes actual synthetic log files, never spawns a process."""
    def __init__(self, argv, *, cwd, env, stdout, stderr, start_new_session, stdout_text="", godot_text="", code=0, ticks=0, log_directory=False):
        self.pid = 123456789  # Never passed to an OS signal; kill seam is injected.
        self.code = code
        self.ticks = ticks
        self.killed = False
        stdout.write(stdout_text.encode())
        stdout.flush()
        path = Path(argv[argv.index("--log-file") + 1])
        if log_directory:
            path.mkdir()
        elif godot_text is not None:
            path.write_text(godot_text)

    def poll(self):
        if self.killed:
            return -9
        if self.ticks:
            self.ticks -= 1
            return None
        return self.code

    def wait(self):
        return -9 if self.killed else self.code


class SupervisorTests(unittest.TestCase):
    def exercise(self, stdout_text=None, godot_text=None, code=0, mode="run", source_error=False,
                 inventory_error=False, log_missing=False, log_directory=False, ticks=0, time_step=0.001, source_timeout=False, factory_error=False, final_write_error=False):
        with tempfile.TemporaryDirectory(prefix="loot-supervisor-fake-", dir="/private/tmp") as temporary:
            root = Path(temporary)
            evidence = root / "evidence"
            evidence.mkdir()
            user = root / "isolated-user"
            user.mkdir()
            save = user / "original-save.json"
            original = b'{"fixture":"never-rewrite-this-original"}'
            save.write_bytes(original)
            calls = {"source": 0, "inventory": 0, "popen": 0, "kill": 0}
            now = [0.0]
            def clock():
                now[0] += time_step
                return now[0]
            def source(deadline):
                calls["source"] += 1
                if source_timeout:
                    raise TimeoutError("synthetic post deadline exhausted")
                if source_error:
                    raise OSError("synthetic post-source I/O error")
                return {"unchanged": True}
            def inventory(deadline):
                calls["inventory"] += 1
                self.assertEqual(save.read_bytes(), original)
                if inventory_error:
                    raise OSError("synthetic inventory I/O error")
                return {"save_sha256": hashlib.sha256(original).hexdigest(), "bytes": len(original)}
            def factory(*args, **kwargs):
                calls["popen"] += 1
                if factory_error:
                    raise OSError("synthetic Popen file error")
                return FakePopen(*args, **kwargs, stdout_text=line(PASS) if stdout_text is None else stdout_text,
                                 godot_text=None if log_missing else line(PASS) if godot_text is None else godot_text,
                                 code=code, ticks=ticks, log_directory=log_directory)
            def kill(proc):
                calls["kill"] += 1
                proc.killed = True
            argv = ["/fake-engine-never-executed", "--log-file", str(evidence / "godot.log")]
            real_write = S.write_json
            def writer(path, value):
                if final_write_error and Path(path).name == "result.json":
                    raise OSError("synthetic final result I/O error")
                return real_write(path, value)
            with patch.object(S, "write_json", writer):
                result = S.execute_child(argv, root, {}, evidence, mode, source, inventory,
                                         popen=factory, clock=clock, sleep=lambda _: None, kill=kill)
            self.assertEqual(calls["popen"], 1)
            self.assertEqual(calls["source"], 1)
            self.assertEqual(calls["inventory"], 1)
            self.assertEqual(save.read_bytes(), original)
            if final_write_error:
                self.assertEqual(result["result_artifact_status"], "UNKNOWN")
                self.assertTrue((evidence / "finalize-failure.json").is_file())
            else:
                self.assertEqual(json.loads((evidence / "result.json").read_text()), result)
            return result, calls

    def test_unique_independent_identical_summaries(self):
        result, _ = self.exercise()
        self.assertEqual(result["result"], "PASS")
        self.assertEqual([row["summary_count"] for row in result["logs"].values()], [1, 1])

    def test_missing_summary(self):
        result, _ = self.exercise(godot_text="Godot banner\n")
        self.assertEqual(result["result"], "FAIL")

    def test_duplicate_stdout_even_if_identical(self):
        result, _ = self.exercise(stdout_text=line(PASS) * 2)
        self.assertEqual(result["result"], "FAIL")
        self.assertEqual(result["logs"]["stdout.log"]["summary_count"], 2)

    def test_duplicate_godot(self):
        result, _ = self.exercise(godot_text=line(PASS) * 3)
        self.assertEqual(result["result"], "FAIL")
        self.assertEqual(result["logs"]["godot.log"]["summary_count"], 3)

    def test_inconsistent_summaries(self):
        result, _ = self.exercise(godot_text=line({**PASS, "received_2760": 2}))
        self.assertEqual(result["result"], "FAIL")

    def test_nonzero_child_cannot_pass(self):
        result, _ = self.exercise(code=1)
        self.assertEqual(result["result"], "FAIL")

    def test_unproven_requires_exit3_and_both_logs(self):
        result, _ = self.exercise(stdout_text=line(UNPROVEN), godot_text=line(UNPROVEN), code=3)
        self.assertEqual(result["result"], "UNPROVEN")
        result, _ = self.exercise(stdout_text=line(UNPROVEN), godot_text=line(UNPROVEN), code=0)
        self.assertEqual(result["result"], "FAIL")

    def test_error_and_resource_tail_matrix(self):
        for message in ["FAIL: fixture", "FAILED fixture", "Failed to load script res://x", "Failed loading resource", "SCRIPT ERROR: bad", "ERROR: bad", "Parse Error: bad", "ObjectDB instances leaked at exit", "Resources still in use at exit", "Resource leak"]:
            for channel in ["stdout", "godot"]:
                with self.subTest(message=message, channel=channel):
                    kwargs = {channel + "_text": line(PASS) + message}  # Deliberately no final newline.
                    result, _ = self.exercise(**kwargs)
                    self.assertEqual(result["result"], "FAIL")

    def test_first_error_stops_live_fake_and_posts(self):
        result, calls = self.exercise(godot_text="FAIL: stop now\n", ticks=100)
        self.assertEqual(result["result"], "FAIL")
        self.assertEqual(calls["kill"], 1)
        self.assertEqual(result["child_exit"], -9)

    def test_bad_json_cannot_skip_post_or_inventory(self):
        result, _ = self.exercise(stdout_text=S.MARKER + "{broken\n")
        self.assertEqual(result["result"], "FAIL")
        self.assertEqual(result["post"]["source"]["status"], "COMPLETE")
        self.assertEqual(result["post"]["inventory"]["status"], "COMPLETE")

    def test_file_error_cannot_skip_posts(self):
        for kwargs in [{"log_missing": True}, {"log_directory": True}]:
            result, _ = self.exercise(**kwargs)
            self.assertEqual(result["result"], "FAIL")
            self.assertEqual(result["post"]["source"]["status"], "COMPLETE")
            self.assertEqual(result["post"]["inventory"]["status"], "COMPLETE")

    def test_source_failure_does_not_skip_inventory(self):
        result, _ = self.exercise(source_error=True)
        self.assertEqual(result["result"], "FAIL")
        self.assertEqual(result["post"]["source"]["status"], "UNKNOWN")
        self.assertEqual(result["post"]["inventory"]["status"], "COMPLETE")

    def test_inventory_failure_keeps_post_source(self):
        result, _ = self.exercise(inventory_error=True)
        self.assertEqual(result["result"], "FAIL")
        self.assertEqual(result["post"]["source"]["status"], "COMPLETE")
        self.assertEqual(result["post"]["inventory"]["status"], "UNKNOWN")

    def test_post_timeout_is_unknown_and_inventory_still_runs(self):
        result, _ = self.exercise(source_timeout=True)
        self.assertEqual(result["result"], "UNCOMPLETE")
        self.assertEqual(result["post"]["source"]["status"], "UNKNOWN")
        self.assertEqual(result["post"]["inventory"]["status"], "COMPLETE")

    def test_popen_file_exception_still_posts(self):
        result, _ = self.exercise(factory_error=True)
        self.assertEqual(result["result"], "FAIL")
        self.assertEqual(result["post"]["source"]["status"], "COMPLETE")
        self.assertEqual(result["post"]["inventory"]["status"], "COMPLETE")

    def test_final_metadata_write_error_does_not_skip_post(self):
        result, _ = self.exercise(final_write_error=True)
        self.assertEqual(result["result"], "FAIL")
        self.assertEqual(result["post"]["source"]["status"], "COMPLETE")
        self.assertEqual(result["post"]["inventory"]["status"], "COMPLETE")

    def test_check_only_has_engine_30s_not_preflight(self):
        result, _ = self.exercise(stdout_text="Godot\n", godot_text="Godot\n", mode="check-only")
        self.assertEqual(result["result"], "PASS")
        self.assertEqual(result["engine_limit_seconds"], 30)
        result, calls = self.exercise(stdout_text="Godot\n", godot_text="Godot\n", mode="check-only", ticks=100, time_step=31)
        self.assertEqual(result["result"], "UNCOMPLETE")
        self.assertEqual(calls["kill"], 1)

    def test_dangling_symlink_is_not_fresh(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as temp:
            path = Path(temp) / "user"
            path.symlink_to(Path(temp) / "absent-target")
            self.assertFalse(path.exists())
            self.assertFalse(S.fresh(path))

    def test_no_history_overwrite_or_process_start(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as temp:
            path = Path(temp) / "result.json"
            path.write_bytes(b"old-result")
            with self.assertRaises(FileExistsError):
                S.execute_child([], Path(temp), {}, Path(temp), "run", lambda _: {}, lambda _: {},
                                popen=lambda *a, **k: self.fail("must never start"))
            self.assertEqual(path.read_bytes(), b"old-result")

    def test_freeze_rejects_dirty_status_and_wrong_candidate_sha(self):
        with tempfile.TemporaryDirectory(dir="/private/tmp") as temp:
            root = Path(temp)
            for name in S.CANDIDATES:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("synthetic candidate\n")
            identity = {"head": "a" * 40, "branch": "test/reviewed", "status_porcelain_z": "?? approved.gd\0"}
            frozen = {"purpose": S.PURPOSE, "suite": S.SCRIPT, "root": str(root), "engine": "/fake",
                      "evidence": str(root / "evidence"), "argv": ["/fake"], "user_name": "fixture",
                      "content_lock_format": S.MANIFEST_FORMAT, "environment_rules": S.ENVIRONMENT_RULES,
                      "identity": identity.copy(), "candidate_sha256": {name: S.digest(root / name) for name in S.CANDIDATES}}
            S.validate_freeze(frozen, root, Path("/fake"), root / "evidence", {"identity": identity}, ["/fake"], "fixture")
            frozen["identity"]["status_porcelain_z"] += "?? unreviewed.gd\0"
            with self.assertRaises(ValueError):
                S.validate_freeze(frozen, root, Path("/fake"), root / "evidence", {"identity": identity}, ["/fake"], "fixture")
            frozen["identity"] = identity.copy()
            frozen["candidate_sha256"][S.CANDIDATES[0]] = "wrong"
            with self.assertRaises(ValueError):
                S.validate_freeze(frozen, root, Path("/fake"), root / "evidence", {"identity": identity}, ["/fake"], "fixture")


class ManifestRevisionTests(unittest.TestCase):
    def test_large_complete_manifest_roundtrip_and_changed_entry_set(self):
        # Synthetic dictionaries only: no repository inventory/content_lock/main.
        count = 181866
        prefix = "/private/synthetic/" + "long-worktree-and-resource-directory/" * 5
        files = {}
        for index in range(count):
            key = prefix + "client/.godot/imported/" + hashlib.sha256(str(index).encode()).hexdigest() + ".ctex"
            files[key] = {"realpath": key.replace("worktree", "resolved"), "bytes": index + 1,
                          "sha256": hashlib.sha256(("content-" + str(index)).encode()).hexdigest()}
        value = {"identity": {"head": "a" * 40, "branch": "test/frozen", "status_porcelain_z": "?? frozen\0"}, "files": files}
        with tempfile.TemporaryDirectory(prefix="loot-manifest-fake-", dir="/private/tmp") as temp:
            path = Path(temp) / "complete.json.gz"
            meta = S.write_manifest(path, value)
            self.assertGreater(meta["raw_bytes"], S.JSON_LIMIT)
            self.assertLessEqual(meta["bytes"], S.MANIFEST_LIMIT)
            S.require_manifest_equal(path, value)
            key = next(iter(files))
            original = files[key].copy()
            for field, replacement in [("sha256", "f" * 64), ("realpath", "/wrong"), ("bytes", -1)]:
                files[key][field] = replacement
                with self.assertRaises(ValueError):
                    S.require_manifest_equal(path, value)
                files[key] = original.copy()
            del files[key]
            with self.assertRaises(ValueError):
                S.require_manifest_equal(path, value)
            files[key] = original
            files[prefix + "extra-path"] = original
            with self.assertRaises(ValueError):
                S.require_manifest_equal(path, value)
            del files[prefix + "extra-path"]
            S.require_manifest_equal(path, value)
            print("SYNTHETIC_MANIFEST_RESULT", json.dumps({"entries": count, **meta, "changed_sha_realpath_size_rejected": True, "added_deleted_path_rejected": True}))

    def test_manifest_caps_and_corruption_leave_failure_evidence(self):
        with tempfile.TemporaryDirectory(prefix="loot-manifest-failure-", dir="/private/tmp") as temp:
            root = Path(temp)
            for bound in ["MANIFEST_RAW_LIMIT", "MANIFEST_LIMIT"]:
                path = root / (bound + ".gz")
                with patch.object(S, bound, 16):
                    with self.assertRaises(ValueError):
                        S.write_manifest(path, {"files": {"long-key": "complete-value" * 50}})
                failure = json.loads(path.with_name(path.name + ".failure.json").read_text())
                self.assertFalse(failure["complete"])
                before = path.read_bytes()
                with self.assertRaises(FileExistsError):
                    S.write_manifest(path, {})
                self.assertEqual(before, path.read_bytes())
            broken = root / "broken.gz"
            broken.write_bytes(b"not a gzip manifest")
            with self.assertRaises((OSError, ValueError)):
                S.require_manifest_equal(broken, {})
            bad = root / "readback-failure.gz"
            with patch.object(S, "read_manifest", side_effect=OSError("synthetic read failure")):
                with self.assertRaises(OSError):
                    S.write_manifest(bad, {"complete": True})
            self.assertTrue(bad.with_name(bad.name + ".failure.json").is_file())

    def test_godot_bin_override_explicitly_refused_before_popen(self):
        for override in ["", "/unapproved/engine"]:
            with self.subTest(override=override), tempfile.TemporaryDirectory(dir="/private/tmp") as temp:
                evidence = Path(temp)
                env = {"GODOT_BIN": override}
                with self.assertRaisesRegex(ValueError, "GODOT_BIN must be unset"):
                    S.validate_environment(env)  # Exact main preflight gate, without calling main.
                with patch.object(S, "subprocess") as process:
                    factory = process.Popen
                    result = S.execute_child([], evidence, env, evidence, "check-only",
                        lambda _: {"unchanged": True}, lambda _: {"bytes": 0}, popen=factory)
                    factory.assert_not_called()
                self.assertEqual(result["result"], "FAIL")
                self.assertTrue(any("GODOT_BIN must be unset" in item for item in result["problems"]))
                self.assertEqual(env["GODOT_BIN"], override)  # Refused, never silently deleted.
                self.assertTrue((evidence / "result.json").is_file())
        S.validate_environment({})


if __name__ == "__main__":
    unittest.main(verbosity=2)
