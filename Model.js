// Pure helpers for Vitals: settings, the machine list, ssh commands, sample
// parsing and formatting. QML imports this file directly; Node loads it as
// CommonJS through the guard at the bottom, which is how dev/test-model.sh
// unit-tests it without a compositor.
//
// The formatting and palette helpers are adapted from OmaStats by Carmine
// Paolino (MIT), https://github.com/crmne/omastats.

.pragma library

var PLUGIN_ID = "supercleanse.vitals"

var SETTINGS = {
  mode: "dock",
  edge: "right",
  width: 200,
  screen: "",
  refreshSeconds: "2",
  historySeconds: 120,
  sampleWhileHidden: false,
  barReadout: "icon"
}

var MODES = ["dock", "window"]
var EDGES = ["right", "left"]

function clamp(v, lo, hi) {
  var n = Number(v)
  if (!isFinite(n)) return lo
  return Math.max(lo, Math.min(hi, n))
}

function num(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : (fallback === undefined ? 0 : fallback)
}

function setting(settings, key) {
  var value = settings ? settings[key] : undefined
  var missing = value === undefined || value === null || (value === "" && key !== "screen")
  return missing ? SETTINGS[key] : value
}

function flag(settings, key) {
  var v = setting(settings, key)
  return v === true || v === "true" || v === 1
}

// Read every setting once, clamped, so the rest of the plugin never has to.
function resolveSettings(settings) {
  var mode = String(setting(settings, "mode")).toLowerCase()
  var edge = String(setting(settings, "edge")).toLowerCase()
  var refresh = clamp(setting(settings, "refreshSeconds"), 1, 30)
  return {
    mode: MODES.indexOf(mode) !== -1 ? mode : SETTINGS.mode,
    edge: EDGES.indexOf(edge) !== -1 ? edge : SETTINGS.edge,
    width: Math.round(clamp(setting(settings, "width"), 160, 360)),
    screen: String(setting(settings, "screen") || ""),
    refreshSeconds: refresh,
    historySeconds: Math.round(clamp(setting(settings, "historySeconds"), 30, 900)),
    sampleWhileHidden: flag(settings, "sampleWhileHidden"),
    barReadout: String(setting(settings, "barReadout")) === "count" ? "count" : "icon"
  }
}

// Samples kept per machine: enough to cover the history at this interval.
function historyLength(historySeconds, refreshSeconds) {
  return Math.round(clamp(Math.ceil(num(historySeconds, 120) / Math.max(1, num(refreshSeconds, 2))), 15, 900))
}

// ---------------------------------------------------------------- machines

function cleanText(value, max) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .trim()
    .slice(0, max || 64)
}

// Anything ssh accepts as a destination: an ssh_config alias, a MagicDNS name,
// user@host, user@100.x.y.z, ssh://user@host:port. Leading dashes would be read
// as options, and whitespace or quotes have no place in a destination.
function validateHost(host) {
  var h = String(host || "")
  if (!h) return "Enter an SSH destination"
  if (h.length > 255) return "That destination is too long"
  if (h.charAt(0) === "-") return "A destination can't start with a dash"
  if (/[\s'"`$;&|<>\\]/.test(h)) return "No spaces, quotes or shell characters"
  return ""
}

function slug(text) {
  var s = String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  return s.slice(0, 32) || "machine"
}

function uniqueId(base, taken) {
  var id = slug(base)
  if (id === "local") id = "machine"
  if (taken.indexOf(id) === -1) return id
  for (var i = 2; i < 1000; i++) {
    if (taken.indexOf(id + "-" + i) === -1) return id + "-" + i
  }
  return id + "-" + Date.now()
}

function localEntry() {
  return { id: "local", alias: "", host: "", enabled: true }
}

// Accepts whatever was in machines.json and returns a clean list: exactly one
// local entry (empty host), unique ids, trimmed text, booleans for enabled.
// Remote entries without a valid destination are dropped.
function normalizeMachines(raw) {
  var list = raw && Array.isArray(raw.machines) ? raw.machines : (Array.isArray(raw) ? raw : [])
  var out = []
  var taken = []
  var haveLocal = false
  for (var i = 0; i < list.length; i++) {
    var m = list[i]
    if (!m || typeof m !== "object") continue
    var host = cleanText(m.host, 255)
    var isLocal = m.id === "local" || (!host && !haveLocal)
    if (isLocal) {
      if (haveLocal) continue
      haveLocal = true
      out.push({ id: "local", alias: cleanText(m.alias, 40), host: "", enabled: m.enabled !== false })
      taken.push("local")
      continue
    }
    if (validateHost(host)) continue
    var alias = cleanText(m.alias, 40) || host
    var id = cleanText(m.id, 40)
    if (!id || id === "local" || taken.indexOf(id) !== -1 || !/^[A-Za-z0-9._-]+$/.test(id)) id = uniqueId(alias, taken)
    taken.push(id)
    out.push({ id: id, alias: alias, host: host, enabled: m.enabled !== false })
  }
  if (!haveLocal) out.unshift(localEntry())
  return out
}

function parseMachinesFile(text) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (e) { return { ok: false, machines: normalizeMachines(null) } }
  return { ok: true, machines: normalizeMachines(data) }
}

function serializeMachines(machines) {
  var clean = normalizeMachines({ machines: machines })
  return JSON.stringify({ version: 1, machines: clean }, null, 2) + "\n"
}

function indexOfMachine(machines, id) {
  for (var i = 0; i < machines.length; i++) if (machines[i].id === id) return i
  return -1
}

// Add or update one entry. Returns { machines, error }.
function upsertMachine(machines, entry) {
  var list = normalizeMachines({ machines: machines })
  var isLocal = entry.id === "local"
  var alias = cleanText(entry.alias, 40)
  var host = isLocal ? "" : cleanText(entry.host, 255)
  if (!isLocal) {
    var err = validateHost(host)
    if (err) return { machines: list, error: err }
  }
  var at = entry.id ? indexOfMachine(list, entry.id) : -1
  if (at === -1) {
    var taken = list.map(function(m) { return m.id })
    list.push({ id: uniqueId(alias || host, taken), alias: alias || host, host: host, enabled: entry.enabled !== false })
  } else {
    list[at] = { id: list[at].id, alias: isLocal ? alias : (alias || host), host: host, enabled: entry.enabled !== false }
  }
  return { machines: list, error: "" }
}

function removeMachine(machines, id) {
  if (id === "local") return normalizeMachines({ machines: machines })
  return normalizeMachines({ machines: machines.filter(function(m) { return m.id !== id }) })
}

function moveMachine(machines, id, delta) {
  var list = normalizeMachines({ machines: machines })
  var at = indexOfMachine(list, id)
  var to = at + delta
  if (at === -1 || to < 0 || to >= list.length) return list
  var item = list.splice(at, 1)[0]
  list.splice(to, 0, item)
  return list
}

function setMachineEnabled(machines, id, enabled) {
  var list = normalizeMachines({ machines: machines })
  var at = indexOfMachine(list, id)
  if (at !== -1) list[at].enabled = enabled === true
  return list
}

// The name shown on a card. The local machine defaults to its short hostname.
function displayAlias(machine, localHostname) {
  if (!machine) return ""
  if (machine.id === "local") return machine.alias || shortHost(localHostname) || "this machine"
  return machine.alias || machine.host
}

function shortHost(name) {
  return cleanText(String(name || "").split(".")[0], 40)
}

// ---------------------------------------------------------------- commands

var SSH_OPTIONS = [
  "-T",
  "-o", "BatchMode=yes",
  "-o", "ConnectTimeout=8",
  "-o", "ServerAliveInterval=10",
  "-o", "ServerAliveCountMax=2"
]

function intervalArg(seconds) {
  var s = clamp(seconds, 1, 30)
  return String(Math.round(s * 10) / 10)
}

// Local: plain sh running the sampler file.
function localCommand(samplerPath, seconds) {
  return ["/bin/sh", String(samplerPath), intervalArg(seconds)]
}

// Remote: ssh runs `sh -s` on the far side and the sampler arrives on stdin,
// so nothing is installed there. The small sh wrapper only redirects the
// file into ssh's stdin; every value travels as its own argument.
function remoteCommand(samplerPath, host, seconds) {
  var argv = ["/bin/sh", "-c", "f=$1; shift; exec ssh \"$@\" < \"$f\"", "vitals-ssh", String(samplerPath)]
  return argv.concat(SSH_OPTIONS, ["--", String(host), "sh", "-s", "--", intervalArg(seconds)])
}

// Reconnect delay after the n-th consecutive failure: 2, 4, 8, 16, 30, 30 … s.
function backoffMs(attempt) {
  var n = Math.max(1, Math.round(num(attempt, 1)))
  return Math.min(30000, 1000 * Math.pow(2, Math.min(5, n)))
}

// A machine is stale when nothing has arrived for three intervals, with a
// floor that leaves room for a slow first sample over ssh.
function staleAfterMs(seconds) {
  return Math.max(8000, Math.round(clamp(seconds, 1, 30) * 3000))
}

// ---------------------------------------------------------------- samples

function parseLine(line) {
  var text = String(line || "")
  if (!text || text.length > 4096 || text.charAt(0) !== "{") return null
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  if (!data || typeof data !== "object") return null
  if (data.type === "hello") {
    return {
      type: "hello",
      os: data.os === "macos" ? "macos" : (data.os === "linux" ? "linux" : "unknown"),
      osName: cleanText(data.osName, 80),
      host: cleanText(data.host, 80),
      cores: Math.max(0, Math.round(num(data.cores)))
    }
  }
  if (data.type === "sample") {
    var total = Math.max(0, num(data.memTotal))
    var used = clamp(data.memUsed, 0, total || 0)
    return {
      type: "sample",
      cpu: clamp(data.cpu, 0, 100),
      user: clamp(data.user, 0, 100),
      sys: clamp(data.sys, 0, 100),
      memUsed: used,
      memTotal: total,
      memPercent: total > 0 ? used / total * 100 : 0,
      rx: Math.max(0, num(data.rx)),
      tx: Math.max(0, num(data.tx)),
      load: Math.max(0, num(data.load))
    }
  }
  if (data.type === "error") return { type: "error", message: cleanText(data.message, 160) }
  return null
}

function pushHistory(arr, value, max) {
  var list = Array.isArray(arr) ? arr : []
  var keep = Math.max(1, max - 1)
  var out = list.length > keep ? list.slice(list.length - keep) : list.slice()
  out.push(Number(value) || 0)
  return out
}

function emptyHistory() {
  return { cpuUser: [], cpuSys: [], mem: [], rx: [], tx: [] }
}

function pushSample(history, sample, max) {
  var h = history || emptyHistory()
  return {
    cpuUser: pushHistory(h.cpuUser, sample.user, max),
    cpuSys: pushHistory(h.cpuSys, sample.sys, max),
    mem: pushHistory(h.mem, sample.memPercent, max),
    rx: pushHistory(h.rx, sample.rx, max),
    tx: pushHistory(h.tx, sample.tx, max)
  }
}

function trimHistory(history, max) {
  var h = history || emptyHistory()
  var cut = function(a) { return Array.isArray(a) && a.length > max ? a.slice(a.length - max) : (a || []) }
  return { cpuUser: cut(h.cpuUser), cpuSys: cut(h.cpuSys), mem: cut(h.mem), rx: cut(h.rx), tx: cut(h.tx) }
}

// Turn ssh's stderr into one short reason for the card.
function sshReason(line) {
  // A ProxyCommand runs under the login shell, whose errors start with
  // "/usr/bin/bash: line 1: ". Keep the message, drop the prefix.
  var t = cleanText(line, 200).replace(/^\S*(ba|z|da|fi)?sh: (line \d+: )?/, "")
  if (!t) return ""
  if (/\b(Terminated|Killed|Hangup)\b/.test(t)) return ""
  var rules = [
    [/Could not resolve hostname/i, "Host not found"],
    [/Connection timed out|Operation timed out|timed out/i, "Connection timed out"],
    [/Connection refused/i, "Connection refused"],
    [/No route to host/i, "No route to host"],
    [/Network is unreachable/i, "Network unreachable"],
    [/Permission denied/i, "SSH key not accepted"],
    [/Host key verification failed/i, "Host key not trusted yet"],
    [/REMOTE HOST IDENTIFICATION HAS CHANGED/i, "Host key changed"],
    [/Connection closed|closed by remote host|Broken pipe/i, "Connection closed"],
    [/Timeout, server .* not responding/i, "Server stopped responding"]
  ]
  for (var i = 0; i < rules.length; i++) if (rules[i][0].test(t)) return rules[i][1]
  if (/^(Warning|debug)/i.test(t)) return ""
  return t.length > 60 ? t.slice(0, 59) + "…" : t
}

// ---------------------------------------------------------------- formatting

var BYTE_UNITS = ["B", "KB", "MB", "GB", "TB", "PB"]

function bytesParts(n) {
  var v = Number(n)
  if (!isFinite(v) || v < 0) v = 0
  var i = 0
  while (v >= 1024 && i < BYTE_UNITS.length - 1) { v /= 1024; i++ }
  var text
  if (i <= 1 || v >= 100) text = String(Math.round(v))
  else text = v.toFixed(1)
  if (text === "1024" && i < BYTE_UNITS.length - 1) { text = "1.0"; i++ }
  return { value: text, unit: BYTE_UNITS[i] }
}

function bytesText(n) {
  var p = bytesParts(n)
  return p.value + " " + p.unit
}

function rateText(n) {
  var p = bytesParts(n)
  return p.value + " " + p.unit + "/s"
}

// Ultra-compact rate: "0", "34K", "1.2M".
function compactRate(n) {
  var v = Number(n)
  if (!isFinite(v) || v < 512) return "0"
  var p = bytesParts(v)
  return p.value + p.unit.charAt(0)
}

// Memory, short enough for the figure column: "18/32G", "3.1/8G", "412M/8G".
function compactPair(used, total) {
  var short = function(n) {
    var p = bytesParts(n)
    var v = Number(p.value)
    var text = v >= 10 ? String(Math.round(v)) : p.value.replace(/\.0$/, "")
    return { value: text, unit: p.unit.charAt(0) }
  }
  var u = short(used), t = short(total)
  if (u.unit === t.unit) return u.value + "/" + t.value + t.unit
  return u.value + u.unit + "/" + t.value + t.unit
}

function pairText(a, b) {
  var pa = bytesParts(a), pb = bytesParts(b)
  if (pa.unit === pb.unit) return pa.value + " / " + pb.value + " " + pb.unit
  return pa.value + " " + pa.unit + " / " + pb.value + " " + pb.unit
}

function percentText(v) {
  return Math.round(clamp(v, 0, 100)) + "%"
}

function loadText(v) {
  var n = num(v, NaN)
  return isFinite(n) ? n.toFixed(2) : "—"
}

// Nerd Font glyphs for the os tag on each card.
function osGlyph(os) {
  if (os === "macos") return String.fromCharCode(0xF179)
  if (os === "linux") return String.fromCharCode(0xF17C)
  return ""
}

function osLabel(os) {
  return os === "macos" ? "macOS" : (os === "linux" ? "Linux" : "")
}

// ---------------------------------------------------------------- theme

// colors.toml carries the theme's named hues (red, blue, …), which the shell's
// palette singleton does not expose.
function parseColorsToml(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m) out[m[1]] = m[2]
  }
  return out
}

function hueOf(c) {
  var q = Qt.color(c)
  return q.hslHue < 0 ? -1 : q.hslHue * 360
}

function hueDistance(a, b) {
  if (a < 0 || b < 0) return 0
  var d = Math.abs(a - b) % 360
  return d > 180 ? 360 - d : d
}

function shiftHue(c, degrees) {
  var q = Qt.color(c)
  var h = q.hslHue < 0 ? 0.6 : (q.hslHue + degrees / 360 + 1) % 1
  return Qt.hsla(h, Math.max(0.45, q.hslSaturation), clamp(q.hslLightness, 0.45, 0.72), 1)
}

// Two graph hues like OmaStats: the theme accent, and a named theme color far
// enough around the wheel to tell the two series apart.
function pickPalette(theme, accent, background, urgent) {
  var t = theme || {}
  var accentHue = hueOf(accent)
  var bgLight = Qt.color(background).hslLightness
  var names = ["blue", "magenta", "cyan", "green", "yellow", "orange", "red"]
  var candidates = []
  for (var i = 0; i < names.length; i++) {
    var c = t[names[i]]
    if (!c) continue
    var q = Qt.color(c)
    if (q.hslSaturation < 0.2 || Math.abs(q.hslLightness - bgLight) < 0.25) continue
    candidates.push({ name: names[i], color: c, dist: hueDistance(accentHue, hueOf(c)) })
  }
  candidates.sort(function(a, b) { return b.dist - a.dist })
  var second = null
  for (var j = 0; j < candidates.length; j++) {
    var cand = candidates[j]
    if ((cand.name === "magenta" || cand.name === "cyan" || cand.name === "blue") && cand.dist >= 50) { second = cand; break }
  }
  if (!second && candidates.length > 0 && candidates[0].dist >= 30) second = candidates[0]
  return {
    series1: accent,
    series2: second ? second.color : shiftHue(accent, 180),
    good: t.green || accent,
    warn: t.yellow || t.orange || accent,
    danger: t.red || urgent
  }
}

if (typeof module !== "undefined") module.exports = {
  PLUGIN_ID: PLUGIN_ID,
  SETTINGS: SETTINGS,
  clamp: clamp,
  resolveSettings: resolveSettings,
  historyLength: historyLength,
  validateHost: validateHost,
  uniqueId: uniqueId,
  normalizeMachines: normalizeMachines,
  parseMachinesFile: parseMachinesFile,
  serializeMachines: serializeMachines,
  upsertMachine: upsertMachine,
  removeMachine: removeMachine,
  moveMachine: moveMachine,
  setMachineEnabled: setMachineEnabled,
  displayAlias: displayAlias,
  localCommand: localCommand,
  remoteCommand: remoteCommand,
  backoffMs: backoffMs,
  staleAfterMs: staleAfterMs,
  parseLine: parseLine,
  pushHistory: pushHistory,
  pushSample: pushSample,
  trimHistory: trimHistory,
  emptyHistory: emptyHistory,
  sshReason: sshReason,
  bytesText: bytesText,
  rateText: rateText,
  compactRate: compactRate,
  compactPair: compactPair,
  pairText: pairText,
  percentText: percentText,
  loadText: loadText,
  osGlyph: osGlyph,
  parseColorsToml: parseColorsToml
}
