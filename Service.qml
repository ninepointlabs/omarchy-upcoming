import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// One instance per shell: watchlist on disk plus TVmaze search/refresh.
// Widgets and the panel all read this, so two monitors never fork the list.
//
// Process boundary: the only program this service starts is python3 from a
// fixed absolute path (Model.PYTHON_CANDIDATES), always with the session
// environment cleared. Every job runs bin/upcoming-ops under bin/bounded-run
// (output caps, deadline, race-free process-group termination). There is no
// shell and no PATH lookup; if no trusted python3 exists, nothing runs.
Item {
  id: root

  property var shell: null
  property var settings: ({})
  property bool active: true

  readonly property string pluginDir: {
    var text = String(Qt.resolvedUrl("."))
    if (text.indexOf("file://") === 0) text = decodeURIComponent(text.substring(7))
    if (text.length > 1 && text.charAt(text.length - 1) === "/") text = text.substring(0, text.length - 1)
    return text
  }
  readonly property var processEnvironment: Model.processEnvironment()

  property string python: ""
  property bool toolsReady: false
  property string toolsError: ""
  property int _pythonCandidate: 0
  property bool _probeStarted: false
  property bool _probeSettled: true

  property var shows: []
  property var hits: []
  property string query: ""
  property bool loaded: false
  property bool pendingSave: false
  property bool searching: false
  property bool refreshing: false
  property string lastError: ""
  property string actionStatus: ""
  property int revision: 0
  property double refreshedAtMs: 0

  readonly property bool busy: searching || refreshing || opsJob.running
  readonly property string barText: Model.barLabel(shows, Date.now())
  readonly property var nextShow: Model.soonest(shows, Date.now())

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function conciseError(value, fallback) {
    return Model.conciseError(value, fallback)
  }

  // ------------------------------------------------------ Trusted python --

  function resolvePython() {
    if (toolsReady || !_probeSettled) return
    _pythonCandidate = 0
    startPythonProbe()
  }

  function startPythonProbe() {
    var candidates = Model.PYTHON_CANDIDATES
    if (_pythonCandidate >= candidates.length) {
      toolsError = "Python 3 was not found in " + candidates.join(", ")
        + " — Upcoming will not run anything from your PATH"
      lastError = toolsError
      return
    }
    _probeStarted = false
    _probeSettled = false
    pythonProbe.command = Model.pythonProbeCommand(candidates[_pythonCandidate])
    pythonProbe.running = true
  }

  Process {
    id: pythonProbe
    running: false
    command: []
    clearEnvironment: true
    environment: root.processEnvironment
    workingDirectory: "/"
    onStarted: root._probeStarted = true
    onExited: function(exitCode) {
      if (root._probeSettled) return
      root._probeSettled = true
      // Missing or too old: try the next fixed path, never a wider search.
      if (!root._probeStarted || exitCode !== 0) { root._pythonCandidate++; root.startPythonProbe(); return }
      root.python = Model.trustedPython(Model.PYTHON_CANDIDATES[root._pythonCandidate])
      root.toolsError = ""
      root.toolsReady = root.python !== ""
      if (root.toolsReady) root.loadWatchlist()
    }
    onRunningChanged: {
      if (running || root._probeSettled || root._probeStarted) return
      root._probeSettled = true
      root._pythonCandidate++
      root.startPythonProbe()
    }
  }

  // ----------------------------------------------------------- Watchlist --

  function loadWatchlist() {
    if (loaded || loadJob.running) return
    if (!toolsReady) { resolvePython(); return }
    if (!loadJob.start(Model.helperCommand(python, pluginDir, "load"), JSON.stringify({ op: "load" })))
      lastError = "Could not start the Upcoming helper"
  }

  HelperJob {
    id: loadJob
    jobEnvironment: root.processEnvironment
    onJobFinished: function(exitCode, stdoutText, stderrText) {
      var failure = Model.jobFailure(exitCode, "The watchlist helper")
      var parsed = Model.parseLoad(stdoutText)
      if (failure !== "" || !parsed.ok) {
        // Not marked loaded: nothing is saved over a watchlist we could not
        // read safely. Refresh (or reopening) tries again.
        root.lastError = root.conciseError(failure || parsed.error, "Could not read the watchlist")
        return
      }
      root.shows = parsed.shows
      root.lastError = parsed.error || ""
      root.loaded = true
      root.revision += 1
      if (root.pendingSave) { root.pendingSave = false; root.persist() }
      if (root.shows.length > 0) root.refresh()
    }
  }

  function persist() {
    if (!loaded) return
    if (saveJob.running) { pendingSave = true; return }
    var payload = JSON.stringify({ op: "save", watchlist: { version: 1, shows: shows } })
    if (!saveJob.start(Model.helperCommand(python, pluginDir, "save"), payload))
      lastError = "Could not save the watchlist"
  }

  HelperJob {
    id: saveJob
    jobEnvironment: root.processEnvironment
    onJobFinished: function(exitCode, stdoutText, stderrText) {
      var failure = Model.jobFailure(exitCode, "The watchlist helper")
      var parsed = Model.parseOps(stdoutText)
      if (failure !== "" || exitCode !== 0 || !parsed.ok)
        root.lastError = root.conciseError(failure || parsed.error, "Could not save the watchlist")
      if (root.pendingSave) { root.pendingSave = false; root.persist() }
    }
  }

  Component.onCompleted: if (active) loadWatchlist()
  onActiveChanged: if (active && !loaded) loadWatchlist()

  // ------------------------------------------------------------- TVmaze --

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
    if (!loaded) { loadWatchlist(); return }
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

  function runOps(payload, kind) {
    if (!toolsReady) {
      lastError = toolsError !== "" ? toolsError : "Still looking for Python 3"
      resolvePython()
      return
    }
    if (opsJob.running) {
      _pending = { payload: payload, kind: kind }
      return
    }
    _kind = kind
    searching = kind === "search"
    refreshing = kind === "refresh" || kind === "add"
    // Query and show ids go over stdin, never argv.
    if (!opsJob.start(Model.helperCommand(python, pluginDir, kind), JSON.stringify(payload))) {
      searching = false
      refreshing = false
      _kind = ""
      lastError = "Could not start the Upcoming helper"
    }
  }

  HelperJob {
    id: opsJob
    jobEnvironment: root.processEnvironment
    onJobFinished: function(exitCode, stdoutText, stderrText) {
      root.finishOps(exitCode, stdoutText, stderrText)
    }
  }

  function finishOps(exitCode, stdoutText, stderrText) {
    searching = false
    refreshing = false
    var kind = _kind
    _kind = ""
    var failure = Model.jobFailure(exitCode, "TVmaze")
    if (failure !== "") { lastError = failure; flushPending(); return }
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
