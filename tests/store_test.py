"""Watchlist store and HTTP body cap tests for bin/upcoming-ops.

Run: /usr/bin/python3 -I -B tests/store_test.py
"""
import http.server
import importlib.machinery
import importlib.util
import json
import os
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OPS = os.path.join(ROOT, "bin", "upcoming-ops")

loader = importlib.machinery.SourceFileLoader("upcoming_ops", OPS)
spec = importlib.util.spec_from_loader("upcoming_ops", loader)
ops = importlib.util.module_from_spec(spec)
loader.exec_module(ops)


def mode(path):
    return stat.S_IMODE(os.lstat(path).st_mode)


class Store(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = os.path.join(self.tmp.name, "home")
        os.mkdir(self.home, 0o700)
        self.state = os.path.join(self.home, ".local", "state", "omarchy-upcoming")
        self.file = os.path.join(self.state, "watchlist.json")
        self.outside = os.path.join(self.tmp.name, "outside")
        os.mkdir(self.outside, 0o700)
        self.victim = os.path.join(self.outside, "victim")
        with open(self.victim, "w") as handle:
            handle.write("do not touch")
        signal.alarm(10)  # a FIFO that blocked would otherwise hang the run

    def tearDown(self):
        signal.alarm(0)
        self.tmp.cleanup()

    def load(self):
        fd = ops.open_state_directory(self.home)
        try:
            return ops.read_watchlist(fd)
        finally:
            os.close(fd)

    def save(self, data=b'{"version":1,"shows":[]}\n'):
        fd = ops.open_state_directory(self.home)
        try:
            ops.write_watchlist(fd, data)
        finally:
            os.close(fd)

    def run_helper(self, request):
        done = subprocess.run(["/usr/bin/python3", "-I", "-S", "-B", OPS, "--home", self.home],
                              input=json.dumps(request).encode(), capture_output=True,
                              env={"PATH": "/usr/bin:/bin", "LC_ALL": "C.UTF-8"}, timeout=10)
        return done.returncode, json.loads(done.stdout)

    def assert_victim_untouched(self):
        with open(self.victim) as handle:
            self.assertEqual(handle.read(), "do not touch")

    # -- normal path ----------------------------------------------------
    def test_missing_file_loads_empty_and_creates_private_dirs(self):
        self.assertIsNone(self.load())
        self.assertEqual(mode(self.state), 0o700)
        self.assertEqual(mode(os.path.join(self.home, ".local")), 0o700)

    def test_round_trip_through_helper(self):
        shows = [{"id": 38052, "name": "Silo"}]
        code, out = self.run_helper({"op": "save", "watchlist": {"version": 1, "shows": shows}})
        self.assertEqual((code, out), (0, {"ok": True}))
        self.assertEqual(mode(self.file), 0o600)
        self.assertEqual(os.listdir(self.state), ["watchlist.json"])
        code, out = self.run_helper({"op": "load"})
        self.assertEqual(code, 0)
        self.assertEqual(out["watchlist"]["shows"], shows)

    def test_existing_loose_modes_are_tightened(self):
        os.makedirs(self.state, 0o755)
        os.chmod(self.state, 0o755)
        with open(self.file, "w") as handle:
            handle.write('{"shows":[]}')
        os.chmod(self.file, 0o644)
        self.assertEqual(self.load(), b'{"shows":[]}')
        self.assertEqual(mode(self.state), 0o700)
        self.assertEqual(mode(self.file), 0o600)

    def test_damaged_json_loads_empty_with_warning(self):
        self.save(b"not json")
        code, out = self.run_helper({"op": "load"})
        self.assertEqual(code, 0)
        self.assertEqual(out["watchlist"]["shows"], [])
        self.assertIn("not readable", out["error"])

    # -- planted links and odd objects ------------------------------------
    def test_symlink_at_watchlist_is_refused_for_read_and_write(self):
        os.makedirs(self.state, 0o700)
        os.symlink(self.victim, self.file)
        with self.assertRaises(ops.StoreError):
            self.load()
        with self.assertRaises(ops.StoreError):
            self.save()
        self.assertTrue(os.path.islink(self.file))
        self.assert_victim_untouched()
        code, out = self.run_helper({"op": "save", "watchlist": {"shows": []}})
        self.assertEqual(code, 9)
        self.assertFalse(out["ok"])
        self.assert_victim_untouched()

    def test_symlink_at_state_directory_is_refused(self):
        os.makedirs(os.path.dirname(self.state), 0o700)
        os.symlink(self.outside, self.state)
        with self.assertRaises(ops.StoreError):
            self.load()
        with self.assertRaises(ops.StoreError):
            self.save()
        self.assertEqual(sorted(os.listdir(self.outside)), ["victim"])

    def test_symlink_at_intermediate_component_is_refused(self):
        os.symlink(self.outside, os.path.join(self.home, ".local"))
        with self.assertRaises(ops.StoreError):
            self.save()
        self.assertEqual(sorted(os.listdir(self.outside)), ["victim"])

    def test_fifo_is_refused_without_blocking(self):
        os.makedirs(self.state, 0o700)
        os.mkfifo(self.file, 0o600)
        with self.assertRaises(ops.StoreError):
            self.load()
        with self.assertRaises(ops.StoreError):
            self.save()

    def test_directory_at_watchlist_is_refused(self):
        os.makedirs(self.file, 0o700)
        with self.assertRaises(ops.StoreError):
            self.load()
        with self.assertRaises(ops.StoreError):
            self.save()

    def test_hard_link_is_refused(self):
        self.save()
        os.link(self.file, os.path.join(self.state, "second"))
        with self.assertRaises(ops.StoreError):
            self.load()

    def test_oversized_file_is_refused(self):
        self.save(b" " * (ops.WATCHLIST_MAX + 1))
        with self.assertRaises(ops.StoreError):
            self.load()

    def test_group_writable_directory_or_file_is_refused(self):
        self.save()
        os.chmod(self.file, 0o620)
        with self.assertRaises(ops.StoreError):
            self.load()
        os.chmod(self.file, 0o600)
        os.chmod(self.state, 0o770)
        with self.assertRaises(ops.StoreError):
            self.load()
        os.chmod(self.state, 0o700)
        os.chmod(self.home, 0o777)
        with self.assertRaises(ops.StoreError):
            self.load()
        os.chmod(self.home, 0o700)

    def test_foreign_owner_is_refused(self):
        self.save()
        real = os.geteuid
        ops.os.geteuid = lambda: real() + 1
        try:
            with self.assertRaises(ops.StoreError):
                self.load()
        finally:
            ops.os.geteuid = real

    def test_planted_temp_name_is_never_followed(self):
        os.makedirs(self.state, 0o700)
        real = ops.secrets.token_hex
        ops.secrets.token_hex = lambda _n: "fixed"
        os.symlink(self.victim, os.path.join(self.state, ".watchlist.json.fixed.tmp"))
        try:
            with self.assertRaises(ops.StoreError):
                self.save()
        finally:
            ops.secrets.token_hex = real
        self.assert_victim_untouched()
        self.assertFalse(os.path.exists(self.file))

    def test_save_rejects_oversized_or_malformed_payloads(self):
        code, out = self.run_helper({"op": "save", "watchlist": {"shows": [{"id": i} for i in range(25)]}})
        self.assertNotEqual(code, 0)
        code, out = self.run_helper({"op": "save", "watchlist": {"shows": [{"name": "x" * 70000}]}})
        self.assertNotEqual(code, 0)
        code, out = self.run_helper({"op": "save", "watchlist": "nope"})
        self.assertNotEqual(code, 0)
        self.assertFalse(os.path.exists(self.file))


class HttpCap(unittest.TestCase):
    def serve(self, handler):
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        return "http://127.0.0.1:%d/" % server.server_address[1]

    def test_endless_chunked_body_is_cut_at_the_cap(self):
        sent = {"bytes": 0}

        class Endless(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_GET(self):
                self.send_response(200)
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                block = b"x" * 65536
                try:
                    for _ in range(200):  # ~13 MiB if nobody stops reading
                        self.wfile.write(b"%x\r\n%s\r\n" % (len(block), block))
                        sent["bytes"] += len(block)
                except OSError:
                    pass

            def log_message(self, *_args):
                pass

        with urllib.request.urlopen(self.serve(Endless), timeout=5) as resp:
            counted = {"n": 0}
            real_read = resp.read

            def counting_read(amt=None):
                data = real_read(amt)
                counted["n"] += len(data)
                return data

            resp.read = counting_read
            self.assertIsNone(ops.read_capped(resp, 100000))
            self.assertLessEqual(counted["n"], 100001)

    def test_declared_oversize_is_refused_before_reading(self):
        class Big(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Length", str(10 ** 9))
                self.end_headers()

            def log_message(self, *_args):
                pass

        with urllib.request.urlopen(self.serve(Big), timeout=5) as resp:
            self.assertIsNone(ops.read_capped(resp, 1000))

    def test_small_body_passes(self):
        class Small(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                body = b'{"ok":true}'
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_args):
                pass

        with urllib.request.urlopen(self.serve(Small), timeout=5) as resp:
            self.assertEqual(ops.read_capped(resp, 1000), b'{"ok":true}')

    def test_redirect_off_host_is_refused(self):
        handler = ops.HostLimitedRedirect()
        req = urllib.request.Request("https://api.tvmaze.com/shows/1")
        with self.assertRaises(urllib.error.HTTPError):
            handler.redirect_request(req, None, 302, "Found", {}, "https://evil.example/")
        with self.assertRaises(urllib.error.HTTPError):
            handler.redirect_request(req, None, 302, "Found", {}, "http://api.tvmaze.com/")


if __name__ == "__main__":
    unittest.main(verbosity=1)
