#!/usr/bin/env node
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { spawnSync } = require("node:child_process");

const root = path.join(__dirname, "..");
const model = {};
vm.createContext(model);
vm.runInContext(fs.readFileSync(path.join(root, "Model.js"), "utf8"), model);

const siloSearch = fs.readFileSync(path.join(root, "tests/fixtures/search-silo.json"), "utf8");
const siloShow = fs.readFileSync(path.join(root, "tests/fixtures/show-silo.json"), "utf8");
const bbShow = fs.readFileSync(path.join(root, "tests/fixtures/show-breaking-bad.json"), "utf8");

const search = model.parseSearch(siloSearch);
assert.equal(search.ok, true);
assert.ok(search.hits.length >= 2);
assert.equal(search.hits[0].id, 38052);
assert.equal(search.hits[0].name, "Silo");
assert.equal(search.hits[0].network, "Apple TV");
assert.equal(search.hits[1].id, 81119);
assert.notEqual(search.hits[0].id, search.hits[1].id);

const html = model.parseSearch(JSON.stringify([{ score: 1, show: { id: 1, name: "<b>Evil</b>", status: "Running", network: { name: "Netflix" } } }]));
assert.equal(html.hits[0].name, "Evil");

const silo = model.parseShow(siloShow);
assert.equal(silo.ok, true);
assert.equal(silo.show.id, 38052);
assert.equal(silo.show.next.season, 4);
assert.equal(silo.show.next.number, 1);
assert.equal(silo.show.next.airdate, "2027-07-09");

const bb = model.parseShow(bbShow);
assert.equal(bb.ok, true);
assert.equal(bb.show.status, "Ended");
assert.equal(bb.show.next, null);

const now = Date.parse("2026-09-10T12:00:00Z");
const shows = model.sortShows([bb.show, silo.show], now);
assert.equal(shows[0].id, 38052);
assert.equal(model.barLabel(shows, now).includes("Silo"), true);
assert.equal(model.barLabel(shows, now).includes("S4E1"), true);
assert.match(model.relativeWhen(silo.show, now), /2027|w|d/);
assert.equal(model.relativeWhen(bb.show, now), "ended");
assert.equal(model.alreadyOnList(shows, 38052), true);
assert.equal(model.withoutShow(shows, 38052).length, 1);

const saved = model.parseWatchlist(JSON.stringify({ shows: [{ id: 38052, name: "Silo", next: silo.show.next }] }));
assert.equal(saved.shows[0].id, 38052);
assert.equal(model.parseWatchlist("not json").ok, false);
assert.equal(model.cleanText("  hi <script>x</script> \u0000", 80), "hi x");

// ---------------------------------------------------------------------------
// Process boundary
// ---------------------------------------------------------------------------
const os = require("node:os");
const PY = "/usr/bin/python3";

const plain = (value) => JSON.parse(JSON.stringify(value));
const env = plain(model.processEnvironment());
assert.deepEqual(Object.keys(env).sort(), ["LC_ALL", "PATH"]);
for (const dir of env.PATH.split(":")) assert.ok(["/usr/bin", "/bin", "/run/current-system/sw/bin"].includes(dir), dir);

for (const kind of ["load", "save", "search", "add", "refresh"]) {
  const cmd = plain(model.helperCommand(PY, root, kind));
  assert.equal(cmd[0], PY);
  assert.deepEqual(cmd.slice(1, 5), ["-I", "-S", "-B", root + "/bin/bounded-run"]);
  const sep = cmd.indexOf("--");
  assert.deepEqual(cmd.slice(sep + 1), [PY, "-I", "-S", "-B", root + "/bin/upcoming-ops"]);
  for (const arg of cmd) assert.ok(!/^(bash|sh|head|mkdir|mktemp|mv|chmod|wc|kill|sleep|python3?)$/.test(arg), arg);
}
assert.deepEqual(plain(model.helperCommand("python3", root, "search")), []);
assert.deepEqual(plain(model.helperCommand("/home/u/bin/python3", root, "search")), []);
assert.deepEqual(plain(model.helperCommand(PY, "relative/dir", "search")), []);
assert.deepEqual(plain(model.helperCommand(PY, "/a/../b", "search")), []);
assert.deepEqual(plain(model.helperCommand(PY, root, "rm")), []);
assert.deepEqual(plain(model.pythonProbeCommand("python3")), []);
assert.equal(plain(model.pythonProbeCommand(PY))[0], PY);
assert.equal(model.jobFailure(124, "TVmaze"), "TVmaze took too long to answer");
assert.equal(model.jobFailure(201, "TVmaze"), "TVmaze sent more data than expected");
assert.equal(model.jobFailure(127), "Could not start the Upcoming helper");
assert.equal(model.jobFailure(0), "");
assert.equal(model.parseLoad('{"ok":true,"watchlist":{"shows":[{"id":5,"name":"X"}]}}').shows[0].id, 5);
assert.equal(model.parseLoad('{"ok":true,"watchlist":{"version":1,"shows":[]}}').error, "");
assert.equal(model.parseLoad('{"ok":false,"error":"watchlist.json is a symlink"}').ok, false);
assert.equal(model.parseLoad('{"ok":true,"watchlist":{"shows":[]},"error":"not readable"}').error, "not readable");

// Every QML process clears the session environment, and no QML file names a
// program except through Model.js.
for (const file of fs.readdirSync(root).filter((f) => f.endsWith(".qml"))) {
  const text = fs.readFileSync(path.join(root, file), "utf8");
  const blocks = text.split(/\n\s*(?=(?:Process|HelperJob)\s*\{)/).slice(1);
  for (const block of blocks) {
    if (/^Process\s*\{/.test(block.trim())) assert.match(block, /clearEnvironment:\s*true/, file + " Process without clearEnvironment");
    if (/^HelperJob\s*\{/.test(block.trim())) assert.match(block, /jobEnvironment:\s*root\.processEnvironment/, file + " HelperJob without environment");
  }
  assert.doesNotMatch(text, /"(bash|\/bin\/bash|sh|head|mkdir|mktemp|mv|chmod|wc|kill|sleep|python3)"/, file);
  assert.doesNotMatch(text, /Quickshell\.env\(/, file + " reads the session environment");
}
const helperJob = fs.readFileSync(path.join(root, "HelperJob.qml"), "utf8");
assert.match(helperJob, /clearEnvironment:\s*true/);
assert.ok(!fs.existsSync(path.join(root, "scripts/bounded-job-wrapper.sh")));

// PATH shadowing and shell/Python start-up hooks: a hostile environment is
// handed straight to the exact argv the service builds, and nothing planted
// runs. (The service clears the environment anyway; this proves the argv
// alone does not depend on it.)
const hostile = fs.mkdtempSync(path.join(os.tmpdir(), "upcoming-shadow-"));
const marker = path.join(hostile, "EXECUTED");
const evil = `#!/bin/sh\necho "$0" >> ${marker}\nexit 0\n`;
for (const name of ["python3", "python", "head", "mkdir", "mktemp", "mv", "chmod", "bash", "sh", "wc", "kill", "sleep", "env"]) {
  fs.writeFileSync(path.join(hostile, name), evil, { mode: 0o755 });
}
fs.writeFileSync(path.join(hostile, "sitecustomize.py"), `open(${JSON.stringify(marker)}, "a").write("sitecustomize\\n")\n`);
fs.writeFileSync(path.join(hostile, "json.py"), `open(${JSON.stringify(marker)}, "a").write("json shadow\\n")\n`);
fs.writeFileSync(path.join(hostile, "startup.py"), `open(${JSON.stringify(marker)}, "a").write("startup\\n")\n`);
const hostileEnv = {
  PATH: hostile + ":/usr/bin:/bin",
  BASH_ENV: path.join(hostile, "sh"),
  ENV: path.join(hostile, "sh"),
  PYTHONPATH: hostile,
  PYTHONSTARTUP: path.join(hostile, "startup.py"),
  PYTHONUSERBASE: hostile,
  LC_ALL: "C.UTF-8"
};
const home = fs.mkdtempSync(path.join(os.tmpdir(), "upcoming-home-"));
function runStore(payload, envOverride) {
  const cmd = plain(model.helperCommand(PY, root, payload.op)).concat(["--home", home]);
  return spawnSync(cmd[0], cmd.slice(1), { input: JSON.stringify(payload), encoding: "utf8", env: envOverride, cwd: hostile });
}
const probe = plain(model.pythonProbeCommand(PY));
assert.equal(spawnSync(probe[0], probe.slice(1), { env: hostileEnv, cwd: hostile }).status, 0);
const saved2 = runStore({ op: "save", watchlist: { version: 1, shows: [{ id: 38052, name: "Silo" }] } }, hostileEnv);
assert.equal(saved2.status, 0, saved2.stdout + saved2.stderr);
const loaded2 = runStore({ op: "load" }, hostileEnv);
assert.equal(loaded2.status, 0, loaded2.stdout + loaded2.stderr);
assert.equal(model.parseLoad(loaded2.stdout).shows[0].name, "Silo");
assert.equal(fs.existsSync(marker), false, fs.existsSync(marker) ? fs.readFileSync(marker, "utf8") : "");
assert.equal(fs.statSync(path.join(home, ".local/state/omarchy-upcoming")).mode & 0o777, 0o700);
assert.equal(fs.statSync(path.join(home, ".local/state/omarchy-upcoming/watchlist.json")).mode & 0o777, 0o600);
fs.rmSync(hostile, { recursive: true, force: true });
fs.rmSync(home, { recursive: true, force: true });

// Live TVmaze, through the same supervised argv and the service's own environment.
function runOps(payload) {
  const kind = payload.op === "show" ? "add" : payload.op;
  const cmd = plain(model.helperCommand(PY, root, kind));
  return spawnSync(cmd[0], cmd.slice(1), { input: JSON.stringify(payload), encoding: "utf8", env });
}

const searchLive = runOps({ op: "search", query: "silo" });
assert.equal(searchLive.status, 0, searchLive.stderr);
const liveHits = JSON.parse(searchLive.stdout);
assert.equal(liveHits.ok, true);
assert.equal(liveHits.hits[0].id, 38052);

const refreshLive = runOps({ op: "refresh", ids: [38052, 169] });
assert.equal(refreshLive.status, 0, refreshLive.stderr);
const liveShows = JSON.parse(refreshLive.stdout);
assert.equal(liveShows.ok, true);
assert.equal(liveShows.shows.length, 2);
const liveSilo = liveShows.shows.find((s) => s.id === 38052);
assert.equal(liveSilo.next.airdate, "2027-07-09");
const liveBb = liveShows.shows.find((s) => s.id === 169);
assert.equal(liveBb.next, null);

const inject = runOps({ op: "search", query: "silo; rm -rf /" });
assert.equal(inject.status === 0 || inject.status === 1, true);
if (inject.status === 0) {
  const inj = JSON.parse(inject.stdout);
  assert.equal(inj.ok, true);
  assert.ok(Array.isArray(inj.hits));
}

const badId = runOps({ op: "show", id: -3 });
assert.notEqual(badId.status, 0);

console.log("PASS: model fixtures, sanitization, live TVmaze search + next-episode");
