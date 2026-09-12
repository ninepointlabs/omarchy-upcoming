import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// One instance per shell: watchlist on disk plus TVmaze search/refresh.
// Widgets and the panel all read this, so two monitors never fork the list.
Item {
  id: root

  property var shell: null
  property var settings: ({})
  property bool active: true

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy-upcoming"
  readonly property string savePath: stateDir + "/watchlist.json"
  readonly property string pluginDir: {
    var text = String(Qt.resolvedUrl("."))
    if (text.indexOf("file://") === 0) text = text.substring(7)
    if (text.length > 1 && text.charAt(text.length - 1) === "/") text = text.substring(0, text.length - 1)
    return text
  }
  readonly property string opsPath: pluginDir + "/bin/upcoming-ops"
  readonly property string wrapperPath: pluginDir + "/scripts/bounded-job-wrapper.sh"

  property var shows: []
  property var hits: []
  property string query: ""
  property bool loaded: false
  property bool dirReady: false
  property bool pendingSave: false
  property bool searching: false
  property bool refreshing: false
  property string lastError: ""
  property string actionStatus: ""
  property int revision: 0
  property double refreshedAtMs: 0

  readonly property bool busy: searching || refreshing || opsProcess.running
  readonly property string barText: Model.barLabel(shows, Date.now())
  readonly property var nextShow: Model.soonest(shows, Date.now())

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function conciseError(value, fallback) {
    return Model.conciseError(value, fallback)
  }

  Process {
    id: mkdir
    command: ["mkdir", "-p", "-m", "700", root.stateDir]
    running: false
    onExited: function(code) {
      root.dirReady = true
      readWatchlist()
    }
  }

  function readWatchlist() {
    if (readProcess.running) return
    readProcess.command = ["head", "-c", "65536", root.savePath]
    readProcess.running = true
  }

  property string _readOut: ""

  Process {
    id: readProcess
    running: false
    command: []
    stdout: StdioCollector { id: readStdout; waitForEnd: true; onStreamFinished: root._readOut = text }
    onExited: function(exitCode) {
      root.applySave(exitCode === 0 ? String(readStdout.text || root._readOut || "") : "")
    }
  }

  function applySave(raw) {
    var parsed = Model.parseWatchlist(raw)
    if (parsed.ok) shows = parsed.shows
    else lastError = parsed.error
    loaded = true
    revision += 1
    if (shows.length > 0) refresh()
  }

  function persist() {
    if (!loaded) return
    if (!dirReady) { pendingSave = true; return }
    if (writeProcess.running) { pendingSave = true; return }
    var payload = JSON.stringify({ version: 1, shows: shows }, null, 1) + "\n"
    // Same-directory temp + rename so a planted symlink at watchlist.json is
    // replaced, never followed. mktemp is 0600; chmod 700 on the dir.
    writeProcess.command = ["/bin/bash", "-c",
      "set -e; d=\"$(dirname \"$0\")\"; mkdir -p -m 700 \"$d\"; " +
      "tmp=\"$(mktemp \"$d/.watchlist.json.XXXXXX\")\"; chmod 600 \"$tmp\"; " +
      "if head -c 65536 > \"$tmp\"; then mv -f \"$tmp\" \"$0\"; else rm -f \"$tmp\"; exit 1; fi",
      root.savePath]
    writeProcess.running = true
    writeProcess.write(payload)
    writeProcess.stdinEnabled = false
    writeProcess.stdinEnabled = true
  }

  Process {
    id: writeProcess
    running: false
    command: []
    stdinEnabled: true
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "Could not save the watchlist"
      if (root.pendingSave) { root.pendingSave = false; root.persist() }
    }
  }

  onDirReadyChanged: if (dirReady && pendingSave) { pendingSave = false; persist() }

  Component.onCompleted: if (active) mkdir.running = true
  onActiveChanged: if (active && !loaded && !mkdir.running) mkdir.running = true

  function addShow(hit) {
    if (!hit || !Model.isPositiveId(hit.id)) return
    if (Model.alreadyOnList(shows, hit.id)) {
      actionStatus = Model.cleanText(hit.name, 40) + " is already on the list"
      statusTimer.restart()
      return
    }
    if (shows.length >= Model.MAX_SHOWS) {
      lastError = "Twenty-four shows is the limit for now"
      return
    }
    lastError = ""
    runOps({ op: "show", id: hit.id }, "add")
  }

  function removeShow(id) {
    shows = Model.withoutShow(shows, id)
    revision += 1
    persist()
  }

  function search(text) {
    var q = Model.sanitizeQuery(text)
    query = q
    hits = []
    if (q.length < 2) {
      lastError = q.length === 0 ? "" : "Type at least two letters"
      return
    }
    lastError = ""
    runOps({ op: "search", query: q }, "search")
  }

  function refresh() {
    if (!loaded) return
    var ids = []
    for (var i = 0; i < shows.length; i++) ids.push(shows[i].id)
    if (ids.length === 0) {
      refreshing = false
      return
    }
    lastError = ""
    runOps({ op: "refresh", ids: ids }, "refresh")
  }

  property var _pending: null
  property string _kind: ""
  property string _payload: ""
  property string _out: ""
  property string _err: ""

  function runOps(payload, kind) {
    if (opsProcess.running) {
      _pending = { payload: payload, kind: kind }
      return
    }
    _kind = kind
    _payload = JSON.stringify(payload)
    searching = kind === "search"
    refreshing = kind === "refresh" || kind === "add"
    _out = ""
    _err = ""
    // Query and show ids go over stdin, never argv. command is a fixed helper.
    opsProcess.command = ["/bin/bash", wrapperPath, "262144", "65536", "1", "--", "python3", "-u", opsPath]
    opsProcess.running = true
    opsProcess.write(_payload)
    opsProcess.stdinEnabled = false
    opsProcess.stdinEnabled = true
  }

  Process {
    id: opsProcess
    running: false
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: opsStdout; waitForEnd: true; onStreamFinished: root._out = text }
    stderr: StdioCollector { id: opsStderr; waitForEnd: true; onStreamFinished: root._err = text }
    onExited: function(exitCode) {
      root.finishOps(exitCode, String(opsStdout.text || root._out || ""), String(opsStderr.text || root._err || ""))
    }
  }

  function finishOps(exitCode, stdoutText, stderrText) {
    searching = false
    refreshing = false
    var kind = _kind
    _kind = ""
    if (exitCode === 201) { lastError = "TVmaze sent more data than expected"; flushPending(); return }
    if (exitCode === 202) { lastError = "TVmaze error output was truncated"; flushPending(); return }
    var parsed = Model.parseOps(stdoutText)
    if (exitCode !== 0 || !parsed.ok) {
      lastError = conciseError(parsed.error || stderrText, "Could not reach TVmaze")
      flushPending()
      return
    }
    lastError = parsed.error || ""
    if (kind === "search") {
      hits = parsed.hits
    } else if (kind === "add" && parsed.shows.length > 0) {
      var show = parsed.shows[0]
      if (!Model.alreadyOnList(shows, show.id) && shows.length < Model.MAX_SHOWS) {
        var next = shows.slice()
        next.push(show)
        shows = Model.sortShows(next, Date.now())
        revision += 1
        persist()
        actionStatus = "Added " + show.name
        statusTimer.restart()
      }
    } else if (kind === "refresh") {
      var merged = []
      var incoming = {}
      for (var i = 0; i < parsed.shows.length; i++) incoming[parsed.shows[i].id] = parsed.shows[i]
      for (var j = 0; j < shows.length; j++) {
        var current = shows[j]
        merged.push(incoming[current.id] || current)
      }
      shows = Model.sortShows(merged, Date.now())
      revision += 1
      refreshedAtMs = Date.now()
      persist()
    }
    flushPending()
  }

  function flushPending() {
    if (!_pending) return
    var next = _pending
    _pending = null
    runOps(next.payload, next.kind)
  }

  Timer {
    id: statusTimer
    interval: 2500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    interval: 6 * 60 * 60 * 1000
    repeat: true
    running: root.active
    onTriggered: root.refresh()
  }
}
