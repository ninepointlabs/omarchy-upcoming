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

const ops = path.join(root, "bin/upcoming-ops");
function runOps(payload) {
  return spawnSync("python3", [ops], { input: JSON.stringify(payload), encoding: "utf8" });
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
