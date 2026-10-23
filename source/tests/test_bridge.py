"""Safety and protocol tests; no PhotoCraft process or user document is touched.

Run with /usr/bin/python3 -m unittest discover -s source/tests -v.
The fake host follows the inspected public engine protocol, including its tab
closing and revision semantics. PNG fixtures use only Python's standard library.
"""
import copy
import importlib.util
import json
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading
import unittest
from unittest import mock
import zlib


SPEC = importlib.util.spec_from_file_location("photocraft_bridge", Path(__file__).resolve().parents[1] / "photocraft_bridge.py")
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


def png(path, width=3, height=2, color=0):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    channels = {0: 1, 2: 3, 6: 4}[color]
    data = b"".join(b"\x00" + bytes([128] * width * channels) for _ in range(height))
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(data)) + chunk(b"IEND", b""))


def document(name="portrait.png", path="/photos/portrait.png", layer=12):
    return {"name": name, "path": path, "width": 3, "height": 2,
            "mode": "Rgb", "depth": 8, "revision": 4, "activeLayer": layer,
            "quickMask": False, "dirty": False,
            "layers": [{"id": layer, "hasMask": False, "children": []}]}


class FakeHost:
    def __init__(self, root, documents=None, active=0):
        self.root = root
        self.docs = copy.deepcopy(documents or [document()])
        self.active = active
        self.calls = []
        self.on_call = None
        self.selected = True
        self.after_open = None

    def session(self):
        return {"active": self.active, "documents": [dict(index=index, **{k: doc[k] for k in ("name", "path", "width", "height", "revision", "dirty")}) for index, doc in enumerate(self.docs)]}

    def call(self, method, params=None):
        params = params or {}
        self.calls.append((method, copy.deepcopy(params)))
        if self.on_call:
            self.on_call(method, params)
        if method == "engine.commands":
            return [{"id": command} for command in bridge.REQUIRED_COMMANDS]
        if method == "ui.inspect":
            return copy.deepcopy({"session": self.session(), "document": self.docs[self.active] if self.active is not None else None, "dialogs": [], "jobs": {"background": True, "focus": None, "running": [], "opening": [], "saving": []}, "cameraRaw": None})
        if method == "app.save":
            png(self.root / params["path"])
            return {"path": params["path"]}
        if method == "app.open":
            path = self.root / params["path"]
            matte = document("matte.png", params["path"], layer=99)
            matte.update(mode="Grayscale", revision=0)
            self.docs.append(matte)
            self.active = len(self.docs) - 1
            if self.after_open:
                self.after_open(self)
            return {"document": self.active}
        if method != "engine.execute":
            raise AssertionError("Unexpected method: " + method)
        command, p = params["command"], params["params"]
        if command == "session.inspect":
            return copy.deepcopy(self.session())
        if command == "document.inspect":
            return copy.deepcopy(self.docs[p["document"]])
        if command == "document.activate":
            self.active = p["document"]
            return {"document": self.active}
        if command == "select.loadSelection":
            assert p["document"] != self.active
            assert p["channel"] == "composite" and p["layer"] == self.docs[p["document"]]["activeLayer"]
            assert self.docs[p["document"]]["mode"] == "Grayscale"
            self.docs[self.active]["revision"] += 1
            self.docs[self.active]["dirty"] = True
            return {"selected": self.selected}
        if command == "layer.layerMask.revealSelection":
            layer = self.docs[self.active]["layers"][0]
            assert p["layer"] == layer["id"] and not layer["hasMask"]
            layer["hasMask"] = True
            self.docs[self.active]["revision"] += 1
            self.docs[self.active]["dirty"] = True
            return None
        if command == "file.close":
            index = p["document"]
            assert self.docs[index]["dirty"] is False
            self.docs.pop(index)
            self.active = None if not self.docs else (self.active - 1 if self.active > index else self.active if self.active < index else min(index, len(self.docs) - 1))
            return None
        raise AssertionError("Unexpected command: " + command)

    def execute(self, command, params=None):
        return self.call("engine.execute", {"command": command, "params": params or {}})

    def commands(self, name):
        return [params["params"] for method, params in self.calls if method == "engine.execute" and params["command"] == name]


class CutoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.engine = self.root / "engine"
        self.engine.write_text("#!/bin/sh\nexit 0\n")
        self.engine.chmod(0o700)
        self.host = FakeHost(self.root)

    def runner(self, args, **kwargs):
        self.assertEqual(kwargs["timeout"], 600)
        png(args[args.index("--mask") + 1])
        return subprocess.CompletedProcess(args, 0, "{}", "")

    def run_cutout(self, **kwargs):
        return bridge.run_cutout(self.host, self.root, self.engine, runner=kwargs.pop("runner", self.runner), **kwargs)

    def assert_kind(self, kind, function):
        with self.assertRaises(bridge.BridgeError) as raised:
            function()
        self.assertEqual(raised.exception.kind, kind)

    def test_selection_preserves_source_and_restores_active_tab(self):
        self.host = FakeHost(self.root, [document(), document("other.png", "/photos/other.png", 14)], active=0)
        result = self.run_cutout()
        self.assertTrue(result["ok"])
        self.assertEqual(self.host.active, 0)
        self.assertEqual(len(self.host.docs), 2)
        self.assertEqual(self.host.docs[0]["path"], "/photos/portrait.png")
        self.assertEqual(self.host.docs[0]["revision"], 5)
        self.assertEqual(len(self.host.commands("select.loadSelection")), 1)
        self.assertEqual(self.host.commands("file.close"), [{"document": 2}])
        self.assertTrue(Path(result["matte"]).is_file())
        self.assertFalse((Path(result["job"]) / "input.png").exists())

    def test_mask_uses_original_layer_and_two_edits(self):
        result = self.run_cutout(output="mask")
        self.assertEqual(result["output"], "mask")
        self.assertTrue(self.host.docs[0]["layers"][0]["hasMask"])
        self.assertEqual(self.host.docs[0]["revision"], 6)
        self.assertEqual(self.host.commands("layer.layerMask.revealSelection"), [{"layer": 12}])

    def test_existing_mask_rejected_before_export(self):
        self.host.docs[0]["layers"][0]["hasMask"] = True
        self.assert_kind("document", lambda: self.run_cutout(output="mask"))
        self.assertNotIn("app.save", [method for method, _ in self.host.calls])
        self.assertEqual(self.host.docs[0]["revision"], 4)

    def test_selection_is_allowed_when_original_layer_has_mask(self):
        self.host.docs[0]["layers"][0]["hasMask"] = True
        self.run_cutout()
        self.assertEqual(self.host.commands("layer.layerMask.revealSelection"), [])
        self.assertTrue(self.host.docs[0]["layers"][0]["hasMask"])

    def test_edit_during_inference_rejects_before_import(self):
        def runner(args, **kwargs):
            result = self.runner(args, **kwargs)
            self.host.docs[0]["revision"] += 1
            return result
        self.assert_kind("stale", lambda: self.run_cutout(runner=runner))
        self.assertNotIn("app.open", [method for method, _ in self.host.calls])
        self.assertEqual(self.host.commands("select.loadSelection"), [])

    def test_active_layer_change_during_inference_rejects(self):
        def runner(args, **kwargs):
            result = self.runner(args, **kwargs)
            self.host.docs[0]["activeLayer"] = 17
            return result
        self.assert_kind("stale", lambda: self.run_cutout(runner=runner))
        self.assertEqual(self.host.commands("select.loadSelection"), [])

    def test_switching_tabs_during_inference_rejects_without_switching_back(self):
        self.host = FakeHost(self.root, [document(), document("other.png", "/photos/other.png", 14)], active=0)
        def runner(args, **kwargs):
            result = self.runner(args, **kwargs)
            self.host.active = 1
            return result
        self.assert_kind("stale", lambda: self.run_cutout(runner=runner))
        self.assertEqual(self.host.active, 1)
        self.assertEqual(self.host.commands("document.activate"), [])

    def test_missing_engine_output_rejects_and_removes_photo_copy(self):
        def runner(args, **kwargs):
            return subprocess.CompletedProcess(args, 0, "", "")
        self.assert_kind("engine", lambda: self.run_cutout(runner=runner))
        self.assertEqual(list(self.root.glob("job-*")), [])
        self.assertEqual(self.host.commands("select.loadSelection"), [])

    def test_wrong_dimensions_reject_before_host_import(self):
        def runner(args, **kwargs):
            png(args[args.index("--mask") + 1], width=4)
            return subprocess.CompletedProcess(args, 0, "", "")
        self.assert_kind("engine", lambda: self.run_cutout(runner=runner))
        self.assertNotIn("app.open", [method for method, _ in self.host.calls])

    def test_rgb_matte_rejects_before_host_import(self):
        def runner(args, **kwargs):
            png(args[args.index("--mask") + 1], color=2)
            return subprocess.CompletedProcess(args, 0, "", "")
        self.assert_kind("engine", lambda: self.run_cutout(runner=runner))
        self.assertEqual(self.host.commands("select.loadSelection"), [])

    def test_engine_timeout_never_imports_or_retries(self):
        runner = mock.Mock(side_effect=subprocess.TimeoutExpired("engine", 600))
        self.assert_kind("engine", lambda: self.run_cutout(runner=runner))
        self.assertEqual(runner.call_count, 1)
        self.assertEqual(self.host.commands("select.loadSelection"), [])

    def test_empty_host_selection_never_creates_a_mask(self):
        self.host.selected = False
        self.assert_kind("empty", lambda: self.run_cutout(output="mask"))
        self.assertEqual(self.host.commands("layer.layerMask.revealSelection"), [])
        self.assertEqual(self.host.commands("file.close"), [{"document": 1}])

    def test_changed_original_during_import_rejects_and_only_closes_own_tab(self):
        self.host.after_open = lambda host: host.docs[0].update(revision=18)
        self.assert_kind("stale", self.run_cutout)
        self.assertEqual(len(self.host.docs), 1)
        self.assertEqual(self.host.docs[0]["revision"], 18)
        self.assertEqual(self.host.commands("select.loadSelection"), [])
        self.assertEqual(self.host.commands("file.close"), [{"document": 1}])

    def test_import_failure_restores_original_among_multiple_tabs(self):
        self.host = FakeHost(self.root, [document(), document("other.png", "/photos/other.png", 14)], active=0)
        self.host.after_open = lambda host: host.docs[-1].update(mode="Rgb")
        self.assert_kind("compatibility", self.run_cutout)
        self.assertEqual(self.host.active, 0)
        self.assertEqual(len(self.host.docs), 2)
        self.assertEqual(self.host.commands("select.loadSelection"), [])
        self.assertEqual(self.host.commands("file.close"), [{"document": 2}])

    def test_wrong_imported_path_never_closes_an_unowned_tab(self):
        self.host.after_open = lambda host: host.docs[-1].update(path="/photos/new-user-file.png")
        self.assert_kind("stale", self.run_cutout)
        self.assertEqual(self.host.commands("file.close"), [])
        self.assertEqual(self.host.commands("select.loadSelection"), [])

    def test_absolute_imported_path_is_also_supported(self):
        self.host.after_open = lambda host: host.docs[-1].update(path=str(self.root / host.docs[-1]["path"]))
        self.assertTrue(self.run_cutout()["ok"])

    def test_edit_between_selection_and_mask_prevents_mask_creation(self):
        def on_call(method, params):
            if method == "engine.execute" and params["command"] == "document.inspect" and self.host.docs[0]["revision"] == 5:
                self.host.docs[0]["revision"] += 1
        self.host.on_call = on_call
        self.assert_kind("stale", lambda: self.run_cutout(output="mask"))
        self.assertEqual(self.host.commands("layer.layerMask.revealSelection"), [])

    def test_dirty_temporary_document_is_kept_with_warning(self):
        def on_call(method, params):
            if method == "engine.execute" and params["command"] == "session.inspect":
                self.host.docs[-1]["dirty"] = True
                self.host.docs[-1]["revision"] += 1
        self.host.on_call = on_call
        result = self.run_cutout()
        self.assertIn("warning", result)
        self.assertEqual(self.host.commands("file.close"), [])
        self.assertEqual(len(self.host.docs), 2)

    def test_matte_identity_change_is_not_closed_even_if_not_dirty(self):
        def on_call(method, params):
            if method == "engine.execute" and params["command"] == "session.inspect":
                self.host.docs[-1]["name"] = "another-user-file.png"
        self.host.on_call = on_call
        result = self.run_cutout()
        self.assertIn("warning", result)
        self.assertEqual(self.host.commands("file.close"), [])

    def test_timeout_after_selection_send_does_not_resend_mutation(self):
        def on_call(method, params):
            if method == "engine.execute" and params["command"] == "select.loadSelection":
                raise bridge.BridgeError("Timeout, completion unknown", "timeout")
        self.host.on_call = on_call
        self.assert_kind("timeout", lambda: self.run_cutout(output="mask"))
        self.assertEqual(len(self.host.commands("select.loadSelection")), 1)
        self.assertEqual(self.host.commands("layer.layerMask.revealSelection"), [])

    def test_realistic_idle_jobs_object_allows_inference(self):
        state = bridge.inspect_ready(self.host)
        self.assertTrue(state["jobs"]["background"])
        self.assertTrue(self.run_cutout()["ok"])

    def test_nonempty_job_queues_and_focus_prevent_export(self):
        for field, value in (("running", [{"id": 3}]), ("opening", [{"job": 3}]), ("saving", [{"job": 3}]), ("focus", 0)):
            with self.subTest(field=field):
                host = FakeHost(self.root)
                call = host.call
                def with_jobs(method, params=None):
                    result = call(method, params)
                    if method == "ui.inspect":
                        result["jobs"][field] = value
                    return result
                host.call = with_jobs
                with self.assertRaises(bridge.BridgeError) as raised:
                    bridge.run_cutout(host, self.root, self.engine, runner=self.runner)
                self.assertEqual(raised.exception.kind, "busy")
                self.assertNotIn("app.save", [method for method, _ in host.calls])

    def test_incompatible_job_shape_fails_closed(self):
        call = self.host.call
        def with_jobs(method, params=None):
            result = call(method, params)
            if method == "ui.inspect":
                result["jobs"] = []
            return result
        self.host.call = with_jobs
        self.assert_kind("compatibility", self.run_cutout)
        self.assertEqual(self.host.commands("select.loadSelection"), [])

    def test_missing_required_command_prevents_export(self):
        call = self.host.call
        def with_missing_command(method, params=None):
            result = call(method, params)
            if method == "engine.commands":
                return [item for item in result if item["id"] != "select.loadSelection"]
            return result
        self.host.call = with_missing_command
        self.assert_kind("compatibility", self.run_cutout)
        self.assertNotIn("app.save", [method for method, _ in self.host.calls])

    def test_cleanup_keeps_user_active_tab(self):
        self.host = FakeHost(self.root, [document(), document("other.png", "/photos/other.png", 14)], active=0)
        initial = self.host.call("ui.inspect")
        self.host.call("app.open", {"path": "matte.png"})
        matte_key = bridge.document_key(self.host.docs[2])
        self.host.active = 1
        self.assertTrue(bridge.cleanup_matte(self.host, 2, matte_key, initial))
        self.assertEqual(self.host.active, 1)
        self.assertEqual(self.host.commands("document.activate"), [])

    def test_cleanup_does_not_close_when_dirty_field_is_missing(self):
        self.host.call("app.open", {"path": "matte.png"})
        matte_key = bridge.document_key(self.host.docs[1])
        self.host.session = lambda: {"active": 1, "documents": [{"index": 0}, {"index": 1}]}
        self.assertFalse(bridge.cleanup_matte(self.host, 1, matte_key))
        self.assertEqual(self.host.commands("file.close"), [])


class FakeSocket:
    def __init__(self, lines):
        self.lines = iter(lines)
        self.sent = []
        self.closed = False

    def makefile(self, mode):
        return self

    def readline(self, limit):
        line = next(self.lines)
        if isinstance(line, BaseException):
            raise line
        return line

    def sendall(self, data):
        self.sent.append(json.loads(data))

    def close(self):
        self.closed = True


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.token = Path(self.temp.name) / "token"
        self.token.write_text("a" * 64)

    def client(self, reply):
        sock = FakeSocket([b'{"id":1,"ok":true,"result":null}\n', reply])
        patcher = mock.patch.object(bridge.socket, "create_connection", return_value=sock)
        patcher.start()
        self.addCleanup(patcher.stop)
        client = bridge.ControlClient(12345, self.token)
        self.addCleanup(client.close)
        return client, sock

    def test_authenticated_loopback_and_sequential_ids(self):
        client, sock = self.client(b'{"id":2,"ok":true,"result":{"selected":true}}\n')
        self.assertEqual(client.execute("select.loadSelection", {"channel": "composite"}), {"selected": True})
        bridge.socket.create_connection.assert_called_once_with(("127.0.0.1", 12345), timeout=65)
        self.assertEqual(sock.sent[0], {"id": 1, "method": "auth", "params": {"token": "a" * 64}})
        self.assertEqual(sock.sent[1]["id"], 2)

    def test_invalid_token_never_connects(self):
        self.token.write_text("bad")
        with mock.patch.object(bridge.socket, "create_connection") as connect:
            with self.assertRaises(bridge.BridgeError) as raised:
                bridge.ControlClient(12345, self.token)
            self.assertEqual(raised.exception.kind, "authentication")
            connect.assert_not_called()

    def test_invalid_envelopes_fail_closed(self):
        for reply in (b"\n", b"[]\n", b'{"id":99,"ok":true}\n', b'{"id":2,"ok":1}\n', b'{"id":2,"ok":true}', b"\xff\n"):
            with self.subTest(reply=reply):
                client, _ = self.client(reply)
                with self.assertRaises(bridge.BridgeError) as raised:
                    client.call("session.inspect")
                self.assertEqual(raised.exception.kind, "protocol")

    def test_host_denial_does_not_resend(self):
        client, sock = self.client(b'{"id":2,"ok":false,"error":"request timed out"}\n')
        with self.assertRaises(bridge.BridgeError) as raised:
            client.execute("select.loadSelection", {"channel": "composite"})
        self.assertEqual(raised.exception.kind, "host")
        self.assertEqual(len(sock.sent), 2)

    def test_socket_timeout_does_not_resend(self):
        client, sock = self.client(socket.timeout("timed out"))
        with self.assertRaises(bridge.BridgeError) as raised:
            client.execute("select.loadSelection", {"channel": "composite"})
        self.assertEqual(raised.exception.kind, "timeout")
        self.assertEqual(len(sock.sent), 2)




class LongInferenceTests(unittest.TestCase):
    def test_read_only_keepalive_unblocks_slow_worker_without_retry(self):
        released = threading.Event()
        calls = []
        class Client:
            def execute(self, command):
                calls.append(command)
                released.set()
        def runner(arguments, **kwargs):
            calls.append("inference")
            self.assertTrue(released.wait(2))
            return subprocess.CompletedProcess(arguments,0,"ok","")
        result = bridge.run_inference(Client(),runner,["engine"],interval=.001)
        self.assertEqual(result.stdout,"ok")
        self.assertEqual(calls.count("inference"),1)
        self.assertEqual(set(calls),{"inference","session.inspect"})

    def test_failed_keepalive_waits_for_worker_and_propagates_without_retry(self):
        released = threading.Event()
        finished = threading.Event()
        calls = []
        class Client:
            def execute(self, command):
                calls.append(command)
                released.set()
                raise bridge.BridgeError("connection closed","connection")
        def runner(arguments, **kwargs):
            calls.append("inference")
            released.wait(2)
            finished.set()
            return subprocess.CompletedProcess(arguments,0,"ok","")
        with self.assertRaises(bridge.BridgeError):
            bridge.run_inference(Client(),runner,["engine"],interval=.001)
        self.assertTrue(finished.is_set())
        self.assertEqual(calls.count("inference"),1)
        self.assertEqual(calls.count("session.inspect"),1)


if __name__ == "__main__":
    unittest.main()
