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
  barReadout: "icon",
  modules: "cpu,memory,network",
  style: "both",
  barLabels: "text",
  temperatureUnit: "Celsius"
}

var MODES = ["dock", "window"]
var EDGES = ["right", "left"]

// Arrays that pass through a Repeater's modelData (or any QML var) can come
// back as list wrappers that fail Array.isArray. Treat any non-string object
// with a length as a list.
function asArray(x) {
  if (Array.isArray(x)) return x
  if (x && typeof x === "object" && typeof x.length === "number") return Array.prototype.slice.call(x)
  return null
}

function isList(x) { return asArray(x) !== null }

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
    barReadout: String(setting(settings, "barReadout")) === "count" ? "count" : "icon",
    modules: parseModules(setting(settings, "modules")),
    style: normalizeStyle(setting(settings, "style")) || "both",
    labels: String(setting(settings, "barLabels")) === "icon" ? "icon" : "text",
    temperatureUnit: String(setting(settings, "temperatureUnit")).toLowerCase() === "fahrenheit" ? "Fahrenheit" : "Celsius"
  }
}

// ---------------------------------------------------------------- modules
//
// The module set, look names and disk options follow OmaStats by Carmine
// Paolino (MIT) so the two read the same.

var MODULES = [
  { id: "cpu",     icon: String.fromCodePoint(0xF0EE0), short: "CPU", label: "CPU",     graph: true,  ring: true },
  { id: "gpu",     icon: String.fromCodePoint(0xF08AE), short: "GPU", label: "GPU",     graph: true,  ring: true },
  { id: "memory",  icon: String.fromCodePoint(0xF035B), short: "MEM", label: "Memory",  graph: true,  ring: true },
  { id: "disks",   icon: String.fromCodePoint(0xF02CA), short: "DSK", label: "Disks",   graph: true,  ring: true },
  { id: "network", icon: String.fromCodePoint(0xF06F3), short: "NET", label: "Network", graph: true,  ring: false },
  { id: "sensors", icon: String.fromCodePoint(0xF050F), short: "SEN", label: "Sensors", graph: false, ring: false },
  { id: "battery", icon: String.fromCodePoint(0xF0079), short: "BAT", label: "Battery", graph: false, ring: true }
]

var MODULE_IDS = ["cpu", "gpu", "memory", "disks", "network", "sensors", "battery"]
var DEFAULT_MODULES = ["cpu", "memory", "network"]
// Modules the sampler only reads when asked; cpu, memory and network are always on.
var EXTRAS = ["gpu", "disks", "sensors", "battery"]
var STYLES = ["graph", "ring", "text", "both", "ring-text"]
var DISK_SHOWS = [
  { value: "speed", label: "Speed" },
  { value: "used", label: "Used" },
  { value: "both", label: "Both" }
]

function moduleDef(id) {
  if (id === "gpuMemory") return { id: "gpuMemory", icon: String.fromCodePoint(0xF035B), short: "VRM", label: "VRAM", graph: true, ring: true }
  for (var i = 0; i < MODULES.length; i++) if (MODULES[i].id === id) return MODULES[i]
  return MODULES[0]
}

function parseModules(raw) {
  var text = isList(raw) ? asArray(raw).join(",") : String(raw || "")
  var parts = text.toLowerCase().split(/[\s,;]+/)
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var id = parts[i]
    if (id === "mem" || id === "ram") id = "memory"
    if (id === "net") id = "network"
    if (id === "disk") id = "disks"
    if (id === "sensor" || id === "temps") id = "sensors"
    if (MODULE_IDS.indexOf(id) !== -1 && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

function normalizeStyle(value) {
  var mode = String(value || "").toLowerCase().replace("+", "-").replace("_", "-")
  if (mode === "ringtext" || mode === "ring-figure") mode = "ring-text"
  if (mode === "graph-text") mode = "both"
  return STYLES.indexOf(mode) !== -1 ? mode : ""
}

// Look choices for one module: rings only where fullness means something.
function styleOptions(module) {
  var def = moduleDef(module)
  if (module === "disks") {
    return [
      { value: "graph", label: "Graph or ring" },
      { value: "text", label: "Figure" },
      { value: "both", label: "Graph or ring, and figure" }
    ]
  }
  var out = []
  if (def.graph) out.push({ value: "graph", label: "Graph" })
  if (def.ring) out.push({ value: "ring", label: "Ring" })
  out.push({ value: "text", label: "Figure" })
  if (def.graph) out.push({ value: "both", label: "Graph and figure" })
  if (def.ring) out.push({ value: "ring-text", label: "Ring and figure" })
  return out
}

// A style that suits the module: a ring look on a module without rings (or
// a graph look on one without graphs) falls back to the nearest fit.
function fitStyle(module, style) {
  var def = moduleDef(module)
  var s = normalizeStyle(style) || "both"
  if (module === "disks") return diskLook(s)
  if (!def.ring && s === "ring") s = "graph"
  if (!def.ring && s === "ring-text") s = "both"
  if (!def.graph && s === "graph") s = def.ring ? "ring" : "text"
  if (!def.graph && s === "both") s = def.ring ? "ring-text" : "text"
  return s
}

function diskLook(style) {
  if (style === "ring") return "graph"
  if (style === "ring-text") return "both"
  return normalizeStyle(style) || "both"
}

function normalizeDiskShow(value) {
  var show = String(value || "").toLowerCase()
  for (var i = 0; i < DISK_SHOWS.length; i++) if (DISK_SHOWS[i].value === show) return show
  return ""
}

function moveInList(list, id, delta) {
  var out = list.slice()
  var from = out.indexOf(id)
  if (from < 0) return out
  var to = Math.max(0, Math.min(out.length - 1, from + delta))
  if (to === from) return out
  out.splice(from, 1)
  out.splice(to, 0, id)
  return out
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
  var list = raw && isList(raw.machines) ? asArray(raw.machines) : (isList(raw) ? asArray(raw) : [])
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
      out.push(withReadouts({ id: "local", alias: cleanText(m.alias, 40), host: "", enabled: m.enabled !== false }, m))
      taken.push("local")
      continue
    }
    if (validateHost(host)) continue
    var alias = cleanText(m.alias, 40) || host
    var id = cleanText(m.id, 40)
    if (!id || id === "local" || taken.indexOf(id) !== -1 || !/^[A-Za-z0-9._-]+$/.test(id)) id = uniqueId(alias, taken)
    taken.push(id)
    out.push(withReadouts({ id: id, alias: alias, host: host, enabled: m.enabled !== false }, m))
  }
  if (!haveLocal) out.unshift(localEntry())
  return out
}

var FILE_VERSION = 2

// Per-machine readout settings (version 2). Every key is optional; a missing
// key follows the global default:
//   modules       ["cpu", "memory", ...] in display order
//   styles        { cpu: "both", memory: "ring-text", ... }
//   disks         [{ disk: "all" | "nvme0n1", show: "speed" | "used" | "both" }]
//   sensors       ["cpu", "nvme/temp1", ...]
//   gpus          "all" or ["0000:03:00.0", ...]
//   showGpuMemory true to add a VRAM readout beside each GPU
function withReadouts(entry, raw) {
  var m = raw || {}
  if (isList(m.modules) || typeof m.modules === "string") entry.modules = parseModules(m.modules)
  if (m.styles && typeof m.styles === "object" && !isList(m.styles)) {
    var styles = {}
    var any = false
    for (var k in m.styles) {
      var st = normalizeStyle(m.styles[k])
      if (MODULE_IDS.indexOf(k) !== -1 && st) { styles[k] = st; any = true }
    }
    if (any) entry.styles = styles
  }
  if (isList(m.disks)) {
    var disks = []
    var seen = []
    for (var i = 0; i < m.disks.length; i++) {
      var d = m.disks[i] || {}
      var name = cleanText(typeof d === "string" ? d : d.disk, 32)
      if (!/^[A-Za-z0-9_]+$/.test(name) || seen.indexOf(name) !== -1) continue
      seen.push(name)
      disks.push({ disk: name, show: normalizeDiskShow(d.show) || "speed" })
    }
    entry.disks = disks
  }
  if (isList(m.sensors)) {
    entry.sensors = asArray(m.sensors).map(function(x) { return cleanText(x, 64) })
      .filter(function(x, at, all) { return /^[A-Za-z0-9_.:\/-]+$/.test(x) && all.indexOf(x) === at })
  }
  if (m.gpus === "all") entry.gpus = "all"
  else if (isList(m.gpus)) entry.gpus = asArray(m.gpus).map(function(x) { return cleanText(x, 64) }).filter(function(x) { return /^[A-Za-z0-9_.:-]+$/.test(x) })
  if (m.showGpuMemory === true) entry.showGpuMemory = true
  return entry
}

// { ok, version, machines }. A file from before version 2 parses as is: its
// machines simply have no readout settings yet and follow the defaults.
function parseMachinesFile(text) {
  var data = null
  try { data = JSON.parse(String(text || "")) } catch (e) { return { ok: false, version: 0, machines: normalizeMachines(null) } }
  if (!data || typeof data !== "object") return { ok: false, version: 0, machines: normalizeMachines(null) }
  return { ok: true, version: Math.round(num(data.version, 1)), machines: normalizeMachines(data) }
}

function serializeMachines(machines) {
  var clean = normalizeMachines({ machines: machines })
  return JSON.stringify({ version: FILE_VERSION, machines: clean }, null, 2) + "\n"
}

// Merge readout settings into one machine. A key set to null goes back to
// following the default.
function updateMachine(machines, id, patch) {
  var list = normalizeMachines({ machines: machines })
  var at = indexOfMachine(list, id)
  if (at === -1) return list
  var next = JSON.parse(JSON.stringify(list[at]))
  for (var k in patch) {
    if (patch[k] === null || patch[k] === undefined) delete next[k]
    else next[k] = patch[k]
  }
  list[at] = normalizeMachines({ machines: [next] }).filter(function(m) { return m.id === next.id })[0] || list[at]
  return normalizeMachines({ machines: list })
}

function resetReadouts(machines, id) {
  return updateMachine(machines, id, { modules: null, styles: null, disks: null, sensors: null, gpus: null, showGpuMemory: null })
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
    // Keep the machine's readout settings when its name or destination changes.
    var kept = JSON.parse(JSON.stringify(list[at]))
    kept.alias = isLocal ? alias : (alias || host)
    kept.host = host
    kept.enabled = entry.enabled !== false
    list[at] = kept
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
function localCommand(samplerPath, seconds, extras, sensorIds) {
  return ["/bin/sh", String(samplerPath), intervalArg(seconds), String(extras || ""), String(sensorIds || "cpu")]
}

// Remote: ssh runs `sh -s` on the far side and the sampler arrives on stdin,
// so nothing is installed there. The small sh wrapper only redirects the
// file into ssh's stdin; every value travels as its own argument.
function remoteCommand(samplerPath, host, seconds, extras, sensorIds) {
  var argv = ["/bin/sh", "-c", "f=$1; shift; exec ssh \"$@\" < \"$f\"", "vitals-ssh", String(samplerPath)]
  return argv.concat(SSH_OPTIONS, ["--", String(host), "sh", "-s", "--", intervalArg(seconds),
    String(extras || "-"), String(sensorIds || "cpu")])
}

// ---------------------------------------------------------------- readouts

// The modules a machine shows, in order.
function machineModules(machine, defaults) {
  if (machine && isList(machine.modules)) return asArray(machine.modules).slice()
  var d = isList(defaults) && defaults.length ? defaults : DEFAULT_MODULES
  return d.slice()
}

// What the machine reported it has. Before its first hello every module is
// offered, since nothing is known yet.
function moduleAvailable(module, info) {
  var caps = info && info.caps
  if (!caps) return true
  if (module === "gpu") return caps.gpu === true
  if (module === "disks") return caps.disks !== false
  if (module === "sensors") return caps.sensors === true
  if (module === "battery") return caps.battery === true
  return true
}

function unavailableReason(module, info) {
  if (moduleAvailable(module, info)) return ""
  if (module === "gpu") return "No GPU found"
  if (module === "battery") return "No battery"
  if (module === "disks") return "No disks found"
  if (module === "sensors") return "No sensors found"
  return ""
}

function machineStyle(machine, module, globalStyle) {
  var own = machine && machine.styles ? normalizeStyle(machine.styles[module]) : ""
  return fitStyle(module, own || globalStyle || "both")
}

function machineDisks(machine) {
  if (machine && isList(machine.disks)) return asArray(machine.disks).map(function(d) { return { disk: d.disk, show: d.show } })
  return [{ disk: "all", show: "speed" }]
}

// Sensors to read: the machine's picks, else the first of the CPU package or
// the battery the machine has.
function machineSensors(machine, info) {
  if (machine && isList(machine.sensors)) return asArray(machine.sensors).slice()
  var list = info && isList(info.sensors) ? asArray(info.sensors) : []
  for (var i = 0; i < list.length; i++) if (list[i].id === "cpu" || list[i].id === "battery") return [list[i].id]
  return list.length > 0 ? [list[0].id] : ["cpu"]
}

function machineGpuIds(machine, info) {
  var all = info && isList(info.gpus) ? asArray(info.gpus).map(function(g) { return g.id }) : []
  if (!machine || machine.gpus === undefined || machine.gpus === null || machine.gpus === "all") return all
  return asArray(machine.gpus).filter(function(id) { return all.length === 0 || all.indexOf(id) !== -1 })
}

// The sampler's second and third arguments for this machine.
function samplerExtras(machine, defaults) {
  var mods = machineModules(machine, defaults)
  return EXTRAS.filter(function(x) { return mods.indexOf(x) !== -1 }).join(",")
}

function samplerSensorIds(machine, info) {
  return machineSensors(machine, info).join(",") || "cpu"
}

// One entry per row on the card: GPUs and disks expand to a row each, the
// way OmaStats expands them in the bar. Modules the machine lacks are left out.
function readouts(machine, info, defaults, globalStyle) {
  var mods = machineModules(machine, defaults)
  var out = []
  for (var i = 0; i < mods.length; i++) {
    var id = mods[i]
    if (!moduleAvailable(id, info)) continue
    var style = machineStyle(machine, id, globalStyle)
    if (id === "gpu") {
      var gpus = machineGpuIds(machine, info)
      if (gpus.length === 0 && !(info && info.caps)) gpus = [""]
      for (var g = 0; g < gpus.length; g++) {
        out.push({ key: "gpu:" + gpus[g], module: "gpu", gpuId: gpus[g], style: style, label: gpus.length > 1 ? gpuShort(info, gpus[g]) : "" })
        if (machine && machine.showGpuMemory) out.push({ key: "vram:" + gpus[g], module: "gpuMemory", gpuId: gpus[g], style: style, label: "VRM" })
      }
      continue
    }
    if (id === "disks") {
      var disks = machineDisks(machine)
      for (var d = 0; d < disks.length; d++) {
        out.push({ key: "disk:" + disks[d].disk, module: "disks", disk: disks[d].disk, show: disks[d].show, style: style, label: disks.length > 1 ? diskShort(disks[d].disk) : "" })
      }
      continue
    }
    out.push({ key: id, module: id, style: style, label: "" })
  }
  return out
}

function gpuShort(info, id) {
  var list = info && isList(info.gpus) ? asArray(info.gpus) : []
  for (var i = 0; i < list.length; i++) {
    if (list[i].id !== id) continue
    if (list[i].vendor === "nvidia") return "NVD"
    if (list[i].vendor === "amd") return "AMD"
    if (list[i].vendor === "intel") return "INT"
  }
  return "GPU"
}

// nvme0n1 -> NV0, sda -> SDA, mmcblk0 -> MC0.
function diskShort(disk) {
  var name = String(disk || "")
  if (!name || name === "all") return "DSK"
  var m = name.match(/^nvme(\d+)n\d+$/)
  if (m) return "NV" + m[1]
  m = name.match(/^mmcblk(\d+)$/)
  if (m) return "MC" + m[1]
  return name.replace(/[^A-Za-z0-9]/g, "").slice(0, 3).toUpperCase() || "DSK"
}

function sensorInfo(info, id) {
  var list = info && isList(info.sensors) ? asArray(info.sensors) : []
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
  return null
}

// One sensor's figure, or null when the machine did not report it.
function sensorReading(sample, info, id, unit) {
  var s = sample || {}
  var meta = sensorInfo(info, id) || { label: id, kind: "temp" }
  if (meta.kind === "fan") {
    var rpm = s.fans ? s.fans[id] : undefined
    if (rpm === undefined || rpm === null || !isFinite(Number(rpm))) return null
    rpm = Number(rpm)
    return { id: id, short: "FAN", label: meta.label, text: rpm > 0 ? String(Math.round(rpm)) : "off", unit: rpm > 0 ? "rpm" : "", kind: "fan" }
  }
  var c = s.temps ? s.temps[id] : undefined
  if (c === undefined || c === null || !isFinite(Number(c))) return null
  var short = id === "cpu" ? "CPU" : (id === "battery" ? "BAT" : (/gpu|amdgpu/i.test(id) ? "GPU" : (/nvme/i.test(id) ? "NVM" : "TMP")))
  return { id: id, short: short, label: meta.label, text: tempText(c, unit), unit: "", kind: "temp", celsius: Number(c) }
}

function tempText(celsius, unit) {
  var c = Number(celsius)
  if (!isFinite(c)) return "\u2014"
  return Math.round(unit === "Fahrenheit" ? c * 9 / 5 + 32 : c) + "\u00b0"
}

function batteryIcon(percent, charging) {
  if (charging) return String.fromCodePoint(0xF0084)
  var icons = [0xF008E, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079]
  return String.fromCodePoint(icons[Math.round(clamp(percent, 0, 100) / 10)])
}

function clockText(minutes) {
  var m = Math.max(0, Math.round(Number(minutes) || 0))
  var h = Math.floor(m / 60)
  var r = m % 60
  return h + ":" + (r < 10 ? "0" : "") + r
}

// "1.2G" or "850M" for a GPU that reports a clock but no load.
function compactFreq(mhz) {
  var m = Number(mhz)
  if (mhz === null || !isFinite(m)) return "\u2014"
  return m >= 1000 ? (m / 1000).toFixed(1) + "G" : Math.round(m) + "M"
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
  if (!text || text.length > 65536 || text.charAt(0) !== "{") return null
  var data
  try { data = JSON.parse(text) } catch (e) { return null }
  if (!data || typeof data !== "object") return null
  if (data.type === "hello") {
    return {
      type: "hello",
      os: data.os === "macos" ? "macos" : (data.os === "linux" ? "linux" : "unknown"),
      osName: cleanText(data.osName, 80),
      host: cleanText(data.host, 80),
      cores: Math.max(0, Math.round(num(data.cores))),
      // Version 1 samplers sent no capabilities; leave caps out so every
      // module stays on offer.
      caps: data.caps && typeof data.caps === "object" ? {
        gpu: data.caps.gpu === true, disks: data.caps.disks !== false,
        sensors: data.caps.sensors === true, battery: data.caps.battery === true
      } : null,
      gpus: (isList(data.gpus) ? data.gpus : []).slice(0, 8).map(function(g) {
        return { id: cleanText(g.id, 64), name: cleanText(g.name, 60), vendor: cleanText(g.vendor, 16), util: g.util === true }
      }),
      disks: (isList(data.disks) ? data.disks : []).slice(0, 32).map(function(d) { return cleanText(d, 32) }),
      sensors: (isList(data.sensors) ? data.sensors : []).slice(0, 64).map(function(x) {
        return { id: cleanText(x.id, 64), label: cleanText(x.label, 48), kind: x.kind === "fan" ? "fan" : "temp" }
      }),
      sensorsNote: cleanText(data.sensorsNote, 120)
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
      load: Math.max(0, num(data.load)),
      gpus: isList(data.gpus) ? data.gpus.slice(0, 8).map(parseGpu) : null,
      disk: data.disk && typeof data.disk === "object" ? parseDisk(data.disk) : null,
      temps: numberMap(data.temps),
      fans: numberMap(data.fans),
      battery: data.battery && typeof data.battery === "object" ? {
        percent: nullableNumber(data.battery.percent, 0, 100),
        status: cleanText(data.battery.status, 20) || "Unknown",
        toEmpty: nullableNumber(data.battery.toEmpty, 0, 100000),
        toFull: nullableNumber(data.battery.toFull, 0, 100000)
      } : null
    }
  }
  if (data.type === "error") return { type: "error", message: cleanText(data.message, 160) }
  return null
}

function nullableNumber(v, lo, hi) {
  if (v === null || v === undefined || v === "" || !isFinite(Number(v))) return null
  return clamp(v, lo, hi)
}

function numberMap(obj) {
  if (!obj || typeof obj !== "object") return null
  var out = {}
  for (var k in obj) {
    var v = Number(obj[k])
    if (isFinite(v)) out[cleanText(k, 64)] = v
  }
  return out
}

function parseGpu(g) {
  var x = g || {}
  return {
    id: cleanText(x.id, 64),
    util: nullableNumber(x.util, 0, 100),
    mhz: nullableNumber(x.mhz, 0, 100000),
    temp: nullableNumber(x.temp, -50, 200),
    memUsed: nullableNumber(x.memUsed, 0, 1e15),
    memTotal: nullableNumber(x.memTotal, 0, 1e15)
  }
}

function parseDisk(d) {
  var per = {}
  if (d.per && typeof d.per === "object") {
    for (var k in d.per) {
      var v = d.per[k]
      if (isList(v) && v.length >= 2) per[cleanText(k, 32)] = [Math.max(0, num(v[0])), Math.max(0, num(v[1]))]
    }
  }
  var space = {}
  if (d.space && typeof d.space === "object") {
    for (var s in d.space) {
      var sv = d.space[s]
      if (isList(sv) && sv.length >= 2 && num(sv[1]) > 0) space[cleanText(s, 32)] = [Math.max(0, num(sv[0])), num(sv[1])]
    }
  }
  return { read: Math.max(0, num(d.read)), write: Math.max(0, num(d.write)), per: per, space: space }
}

function gpuSample(sample, id) {
  var list = sample && isList(sample.gpus) ? asArray(sample.gpus) : []
  for (var i = 0; i < list.length; i++) if (!id || list[i].id === id) return list[i]
  return null
}

function gpuMemoryPercent(g) {
  if (!g || g.memUsed === null || g.memTotal === null || !(g.memTotal > 0)) return null
  return Math.min(100, g.memUsed / g.memTotal * 100)
}

// Read/write rates for one disk entry ("all" or a device name).
function diskRates(sample, disk) {
  var d = sample && sample.disk
  if (!d) return null
  if (!disk || disk === "all") return [d.read, d.write]
  return d.per[disk] || null
}

function diskSpace(sample, disk) {
  var d = sample && sample.disk
  if (!d || !d.space) return null
  return d.space[disk || "all"] || null
}

function pushHistory(arr, value, max) {
  var list = isList(arr) ? asArray(arr) : []
  var keep = Math.max(1, max - 1)
  var out = list.length > keep ? list.slice(list.length - keep) : list.slice()
  out.push(Number(value) || 0)
  return out
}

function emptyHistory() {
  return { cpuUser: [], cpuSys: [], mem: [], rx: [], tx: [], gpu: {}, gpuMem: {}, diskRead: {}, diskWrite: {}, battery: [] }
}

function pushKeyed(map, key, value, max) {
  var next = {}
  for (var k in (map || {})) next[k] = map[k]
  next[key] = pushHistory(next[key], value, max)
  return next
}

function pushSample(history, sample, max) {
  var h = history || emptyHistory()
  var out = {
    cpuUser: pushHistory(h.cpuUser, sample.user, max),
    cpuSys: pushHistory(h.cpuSys, sample.sys, max),
    mem: pushHistory(h.mem, sample.memPercent, max),
    rx: pushHistory(h.rx, sample.rx, max),
    tx: pushHistory(h.tx, sample.tx, max),
    gpu: h.gpu || {}, gpuMem: h.gpuMem || {}, diskRead: h.diskRead || {}, diskWrite: h.diskWrite || {},
    battery: h.battery || []
  }
  var gpus = isList(sample.gpus) ? asArray(sample.gpus) : []
  for (var i = 0; i < gpus.length; i++) {
    out.gpu = pushKeyed(out.gpu, gpus[i].id, gpus[i].util === null ? 0 : gpus[i].util, max)
    var gm = gpuMemoryPercent(gpus[i])
    if (gm !== null) out.gpuMem = pushKeyed(out.gpuMem, gpus[i].id, gm, max)
  }
  if (sample.disk) {
    out.diskRead = pushKeyed(out.diskRead, "all", sample.disk.read, max)
    out.diskWrite = pushKeyed(out.diskWrite, "all", sample.disk.write, max)
    for (var d in sample.disk.per) {
      out.diskRead = pushKeyed(out.diskRead, d, sample.disk.per[d][0], max)
      out.diskWrite = pushKeyed(out.diskWrite, d, sample.disk.per[d][1], max)
    }
  }
  if (sample.battery && sample.battery.percent !== null) out.battery = pushHistory(h.battery, sample.battery.percent, max)
  return out
}

function trimHistory(history, max) {
  var h = history || emptyHistory()
  var cut = function(a) { var l = asArray(a) || []; return l.length > max ? l.slice(l.length - max) : l }
  var cutMap = function(m) { var o = {}; for (var k in (m || {})) o[k] = cut(m[k]); return o }
  return {
    cpuUser: cut(h.cpuUser), cpuSys: cut(h.cpuSys), mem: cut(h.mem), rx: cut(h.rx), tx: cut(h.tx),
    gpu: cutMap(h.gpu), gpuMem: cutMap(h.gpuMem), diskRead: cutMap(h.diskRead), diskWrite: cutMap(h.diskWrite),
    battery: cut(h.battery)
  }
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
  parseColorsToml: parseColorsToml,
  FILE_VERSION: FILE_VERSION,
  MODULE_IDS: MODULE_IDS,
  parseModules: parseModules,
  normalizeStyle: normalizeStyle,
  styleOptions: styleOptions,
  fitStyle: fitStyle,
  moveInList: moveInList,
  updateMachine: updateMachine,
  resetReadouts: resetReadouts,
  machineModules: machineModules,
  moduleAvailable: moduleAvailable,
  unavailableReason: unavailableReason,
  machineStyle: machineStyle,
  machineDisks: machineDisks,
  machineSensors: machineSensors,
  machineGpuIds: machineGpuIds,
  samplerExtras: samplerExtras,
  samplerSensorIds: samplerSensorIds,
  readouts: readouts,
  diskShort: diskShort,
  sensorReading: sensorReading,
  tempText: tempText,
  diskRates: diskRates,
  diskSpace: diskSpace,
  gpuSample: gpuSample,
  compactFreq: compactFreq,
  clockText: clockText
}
