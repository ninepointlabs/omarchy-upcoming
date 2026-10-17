#!/usr/bin/env node
// About page: facts from the repo, versions, the support email, and a privacy
// statement that names every network host. No network, no real home.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.join(__dirname, "..");
const model = {};
vm.createContext(model);
vm.runInContext(fs.readFileSync(path.join(root, "Model.js"), "utf8"), model);

const manifest = fs.readFileSync(path.join(root, "manifest.json"), "utf8");
assert.equal(model.manifestVersion(manifest), JSON.parse(manifest).version);
assert.equal(model.manifestVersion("not json"), "");
assert.equal(model.manifestVersion('{"version":"1.0 <b>"}'), "");
assert.equal(JSON.parse(manifest).author, "Nine Point Labs");
assert.equal(model.ABOUT.name, JSON.parse(manifest).name);

const license = fs.readFileSync(path.join(root, "LICENSE"), "utf8");
assert.ok(license.startsWith(model.ABOUT.license));
assert.ok(license.includes(model.ABOUT.copyright.replace("©", "Copyright (c)")));
assert.equal(model.ABOUT.organization, "Nine Point Labs");
assert.equal(model.ABOUT.supportEmail, "help@ninepointlabs.com");
const reflowed = model.reflowLicense(license);
assert.ok(reflowed.startsWith("MIT License\n\nCopyright (c) 2026 Nine Point Labs\n\nPermission"));
assert.ok(!reflowed.includes("a copy\nof"));

// No "Ninepoint" spelling left anywhere in the plugin.
for (const file of fs.readdirSync(root).filter((f) => /\.(qml|js|json|md)$|^LICENSE$/.test(f)))
  assert.doesNotMatch(fs.readFileSync(path.join(root, file), "utf8"), /Ninepoint Labs|NINEPOINT LABS/, file);

// TVmaze data is CC BY-SA 4.0: credited on the page and in the notices.
assert.match(model.ABOUT.dataCredit, /TVmaze.*CC BY-SA 4\.0/);
assert.match(fs.readFileSync(path.join(root, "THIRD_PARTY_NOTICES.md"), "utf8"), /CC BY-SA 4\.0/);

assert.equal(model.probedVersion((major, minor) => major === 6 && minor <= 11, 6), "6.11");
assert.equal(model.probedVersion((major, minor) => major === 0 && minor <= 3, 0), "0.3");
assert.equal(model.probedVersion(() => false, 6), "");
assert.equal(model.probedVersion(null, 6), "");

const details = model.aboutDetails("0.1.1", "0.3", "6.11", "3.14.7", "linux, wayland");
assert.equal(details, "Upcoming 0.1.1\nQuickshell 0.3, Qt 6.11, Python 3.14.7\nlinux, wayland");
assert.equal(model.aboutDetails("", "", "", "", ""), "Upcoming unknown version\nversions unknown\nunknown platform");
const mail = model.supportMailto("0.1.1", details);
assert.ok(mail.startsWith("mailto:help@ninepointlabs.com?subject=Upcoming%200.1.1&body="));
assert.ok(decodeURIComponent(mail.split("&body=")[1]).endsWith("Python 3.14.7\nlinux, wayland"));

assert.equal(model.parseLoad('{"ok":true,"watchlist":{"shows":[]},"python":"3.14.7"}').python, "3.14.7");
assert.equal(model.parseLoad('{"ok":true,"watchlist":{"shows":[]},"python":"3.14; rm"}').python, "");
assert.equal(model.parseLoad('{"ok":true,"watchlist":{"shows":[]}}').python, "");

// Privacy: every host named in the code must appear in the statement. Hosts
// that the plugin never contacts are listed here with the reason.
const NOT_CONTACTED = {
  "github.com": "only inside the User-Agent string sent to TVmaze",
  "www.tvmaze.com": "About page link back to TVmaze, opened in the browser",
};
const sources = fs.readdirSync(root).filter((f) => /\.(qml|js)$/.test(f))
  .concat(fs.readdirSync(path.join(root, "bin")).map((f) => path.join("bin", f)));
const hosts = new Set();
for (const file of sources) {
  const text = fs.readFileSync(path.join(root, file), "utf8");
  for (const m of text.matchAll(/\b(?:https?|wss?):\/\/([A-Za-z0-9.-]+)/g)) hosts.add(m[1].toLowerCase());
  for (const m of text.matchAll(/^\s*HOST\s*=\s*"([^"]+)"/gm)) hosts.add(m[1].toLowerCase());
  assert.doesNotMatch(text, /XMLHttpRequest|\bImage\s*\{|AnimatedImage|WebSocket\s*\{/, file + " fetches outside the helper");
}
assert.ok(hosts.has("api.tvmaze.com"));
for (const host of hosts) {
  if (NOT_CONTACTED[host]) continue;
  assert.ok(model.PRIVACY.includes(host), host + " is not named in the privacy statement");
}
assert.ok(model.PRIVACY.includes("no telemetry"));
assert.ok(model.PRIVACY.includes("~/.local/state/omarchy-upcoming/watchlist.json (0600)"));

// The About page is in the panel and reachable over IPC.
const panel = fs.readFileSync(path.join(root, "Panel.qml"), "utf8");
assert.match(panel, /objectName: "aboutButton"/);
assert.match(panel, /onCloseRequested: root\.showAbout \? root\.hideAboutPage\(\) : root\.close\(\)/);
assert.match(fs.readFileSync(path.join(root, "BarWidget.qml"), "utf8"), /function about\(\): void/);

console.log("PASS: About facts, support email, privacy hosts");
