// Pure JS: TVmaze search/show parsing, watchlist helpers, bar label.
// No QML or Qt types, so this stays testable under node.

var MAX_SHOWS = 24
var QUERY_MAX = 80
var NAME_MAX = 80
var NETWORK_MAX = 40
var EPISODE_NAME_MAX = 80
var ERROR_MAX = 200
var MS_PER_DAY = 86400000
var MS_PER_HOUR = 3600000

function cleanText(value, limit) {
  var text = String(value === undefined || value === null ? "" : value)
  text = text.replace(/\u0000/g, "")
  text = text.replace(/[\u0001-\u0008\u000b\u000c\u000e-\u001f]/g, "")
  text = text.replace(/<[^>]*>/g, "")
  text = text.replace(/\s+/g, " ").replace(/^ | $/g, "")
  var max = Number(limit)
  if (!isFinite(max) || max <= 0) max = 200
  if (text.length > max) text = text.substring(0, max)
  return text
}

function conciseError(value, fallback) {
  var text = cleanText(value || fallback || "Request failed", ERROR_MAX)
  return text.length > 180 ? text.substring(0, 177) + "…" : text
}

function asInt(value) {
  var n = Number(value)
  return isFinite(n) ? Math.trunc(n) : 0
}

function isPositiveId(value) {
  var n = asInt(value)
  return n > 0 && n < 100000000
}

function sanitizeQuery(value) {
  var text = cleanText(value, QUERY_MAX)
  return text
}

function networkName(show) {
  if (!show || typeof show !== "object") return ""
  var net = show.network || show.webChannel || null
  if (!net || typeof net !== "object") return ""
  return cleanText(net.name, NETWORK_MAX)
}

function parseSearchHit(raw) {
  if (!raw || typeof raw !== "object") return null
  var show = raw.show && typeof raw.show === "object" ? raw.show : raw
  if (!isPositiveId(show.id)) return null
  var name = cleanText(show.name, NAME_MAX)
  if (name === "") return null
  return {
    id: asInt(show.id),
    name: name,
    premiered: cleanText(show.premiered, 10),
    network: networkName(show),
    status: cleanText(show.status, 24),
    score: Number(raw.score)
  }
}

function parseSearch(text) {
  var parsed
  try { parsed = JSON.parse(String(text || "")) } catch (e) {
    return { ok: false, error: "Could not read search results", hits: [] }
  }
  if (!Array.isArray(parsed)) return { ok: false, error: "Unexpected search response", hits: [] }
  var hits = []
  var seen = {}
  for (var i = 0; i < parsed.length && hits.length < 12; i++) {
    var hit = parseSearchHit(parsed[i])
    if (!hit || seen[hit.id]) continue
    seen[hit.id] = true
    hits.push(hit)
  }
  return { ok: true, hits: hits }
}

function parseNextEpisode(raw) {
  if (!raw || typeof raw !== "object") return null
  var airdate = cleanText(raw.airdate, 10)
  var airstamp = cleanText(raw.airstamp, 32)
  if (airdate === "" && airstamp === "") return null
  return {
    name: cleanText(raw.name, EPISODE_NAME_MAX),
    season: asInt(raw.season),
    number: asInt(raw.number),
    airdate: airdate,
    airtime: cleanText(raw.airtime, 8),
    airstamp: airstamp
  }
}

function parseShow(text) {
  var parsed
  try { parsed = JSON.parse(String(text || "")) } catch (e) {
    return { ok: false, error: "Could not read show" }
  }
  if (!parsed || typeof parsed !== "object" || !isPositiveId(parsed.id))
    return { ok: false, error: "Unexpected show response" }
  var embedded = parsed._embedded && typeof parsed._embedded === "object" ? parsed._embedded : {}
  return {
    ok: true,
    show: {
      id: asInt(parsed.id),
      name: cleanText(parsed.name, NAME_MAX),
      premiered: cleanText(parsed.premiered, 10),
      network: networkName(parsed),
      status: cleanText(parsed.status, 24),
      next: parseNextEpisode(embedded.nextepisode)
    }
  }
}

function nextMs(show) {
  if (!show || !show.next) return 0
  var stamp = String(show.next.airstamp || "")
  if (stamp !== "") {
    var t = Date.parse(stamp)
    if (isFinite(t)) return t
  }
  var day = String(show.next.airdate || "")
  if (/^\d{4}-\d{2}-\d{2}$/.test(day)) {
    var t2 = Date.parse(day + "T12:00:00Z")
    if (isFinite(t2)) return t2
  }
  return 0
}

function isUpcoming(show, nowMs) {
  var t = nextMs(show)
  return t > 0 && t >= Number(nowMs) - MS_PER_HOUR
}

function sortShows(shows, nowMs) {
  var list = Array.isArray(shows) ? shows.slice() : []
  var now = Number(nowMs) || Date.now()
  list.sort(function(a, b) {
    var au = isUpcoming(a, now)
    var bu = isUpcoming(b, now)
    if (au !== bu) return au ? -1 : 1
    var at = nextMs(a)
    var bt = nextMs(b)
    if (au && at !== bt) return at - bt
    var an = String((a && a.name) || "")
    var bn = String((b && b.name) || "")
    if (an < bn) return -1
    if (an > bn) return 1
    return 0
  })
  return list
}

function episodeCode(next) {
  if (!next) return ""
  var s = asInt(next.season)
  var n = asInt(next.number)
  if (s <= 0 && n <= 0) return ""
  var out = "S" + s
  if (n > 0) out += "E" + n
  return out
}

function relativeWhen(show, nowMs) {
  var t = nextMs(show)
  if (t <= 0) {
    var status = cleanText(show && show.status, 24)
    if (status === "Ended" || status === "To Be Determined") return status === "Ended" ? "ended" : "TBA"
    return "no date"
  }
  var now = Number(nowMs) || Date.now()
  var delta = t - now
  if (delta < -MS_PER_HOUR) return "aired"
  if (delta < MS_PER_HOUR * 18) {
    var hours = Math.max(1, Math.round(delta / MS_PER_HOUR))
    if (delta < MS_PER_HOUR) return "soon"
    return "in " + hours + "h"
  }
  var days = Math.round(delta / MS_PER_DAY)
  if (days <= 1) return "tomorrow"
  if (days < 14) return "in " + days + "d"
  if (days < 60) return "in " + Math.round(days / 7) + "w"
  var date = new Date(t)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[date.getUTCMonth()] + " " + date.getUTCDate() + " " + date.getUTCFullYear()
}

function showSubtitle(show, nowMs) {
  if (!show) return ""
  var bits = []
  if (show.network) bits.push(show.network)
  if (show.premiered && /^\d{4}/.test(show.premiered)) bits.push(show.premiered.substring(0, 4))
  var when = relativeWhen(show, nowMs)
  var code = episodeCode(show.next)
  if (isUpcoming(show, nowMs) && code) bits.push(code + " · " + when)
  else if (isUpcoming(show, nowMs)) bits.push(when)
  else if (when) bits.push(when)
  return bits.join(" · ")
}

function soonest(shows, nowMs) {
  var list = sortShows(shows, nowMs)
  var now = Number(nowMs) || Date.now()
  for (var i = 0; i < list.length; i++) {
    if (isUpcoming(list[i], now)) return list[i]
  }
  return null
}

function barLabel(shows, nowMs) {
  var next = soonest(shows, nowMs)
  if (!next) return ""
  var code = episodeCode(next.next)
  var when = relativeWhen(next, nowMs)
  var name = cleanText(next.name, 28)
  if (code) return name + " · " + code + " " + when
  return name + " · " + when
}

function parseWatchlist(text) {
  if (!text || String(text).replace(/^\s+|\s+$/g, "") === "") return { ok: true, shows: [] }
  var parsed
  try { parsed = JSON.parse(String(text)) } catch (e) {
    return { ok: false, error: "Watchlist file is not readable", shows: [] }
  }
  var raw = parsed && Array.isArray(parsed.shows) ? parsed.shows : (Array.isArray(parsed) ? parsed : [])
  var shows = []
  var seen = {}
  for (var i = 0; i < raw.length && shows.length < MAX_SHOWS; i++) {
    var item = raw[i]
    if (!item || typeof item !== "object" || !isPositiveId(item.id)) continue
    var id = asInt(item.id)
    if (seen[id]) continue
    seen[id] = true
    shows.push({
      id: id,
      name: cleanText(item.name, NAME_MAX),
      premiered: cleanText(item.premiered, 10),
      network: cleanText(item.network, NETWORK_MAX),
      status: cleanText(item.status, 24),
      next: parseNextEpisode(item.next),
      fetchedAt: asInt(item.fetchedAt)
    })
  }
  return { ok: true, shows: shows }
}

function alreadyOnList(shows, id) {
  var want = asInt(id)
  var list = Array.isArray(shows) ? shows : []
  for (var i = 0; i < list.length; i++) if (asInt(list[i].id) === want) return true
  return false
}

function withoutShow(shows, id) {
  var want = asInt(id)
  var out = []
  var list = Array.isArray(shows) ? shows : []
  for (var i = 0; i < list.length; i++) if (asInt(list[i].id) !== want) out.push(list[i])
  return out
}

function parseOps(text) {
  var parsed
  try { parsed = JSON.parse(String(text || "")) } catch (e) {
    return { ok: false, error: conciseError(text, "Could not talk to TVmaze") }
  }
  if (!parsed || typeof parsed !== "object") return { ok: false, error: "Unexpected response" }
  if (parsed.ok === false) return { ok: false, error: conciseError(parsed.error, "Request failed"), shows: [], hits: [] }
  return {
    ok: true,
    shows: Array.isArray(parsed.shows) ? parseWatchlist(JSON.stringify({ shows: parsed.shows })).shows : [],
    hits: Array.isArray(parsed.hits) ? parsed.hits.map(parseSearchHit).filter(function(h) { return h }) : [],
    error: ""
  }
}

function opsCommand(scriptPath) {
  return [
    "/bin/bash", scriptPath,
    "262144", "65536", "1", "--",
    "python3", "-u"
  ]
}
