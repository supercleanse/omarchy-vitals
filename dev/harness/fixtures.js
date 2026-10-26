.pragma library

// Fictional machines and synthetic histories for the offscreen harness only.
// Nothing here is read by the plugin itself.

function wave(n, base, amp, period, phase, jitter, seed) {
  var out = []
  var s = seed || 1
  for (var i = 0; i < n; i++) {
    s = (s * 9301 + 49297) % 233280
    var noise = (s / 233280 - 0.5) * 2 * (jitter || 0)
    out.push(Math.max(0, base + amp * Math.sin((i + phase) / period) + noise))
  }
  return out
}

function spikes(n, base, peak, every, seed) {
  var out = []
  var s = seed || 7
  for (var i = 0; i < n; i++) {
    s = (s * 9301 + 49297) % 233280
    var r = s / 233280
    out.push(i % every < 3 ? peak * (0.4 + r * 0.6) : base * (0.3 + r))
  }
  return out
}

function last(list) { return list[list.length - 1] }

function linkFor(status, os, osName, cores, total, cpuBase, memBase, netBase, seed) {
  var n = 60
  var user = wave(n, cpuBase * 0.7, cpuBase * 0.35, 6, seed, cpuBase * 0.2, seed)
  var sys = wave(n, cpuBase * 0.3, cpuBase * 0.12, 4, seed * 2, cpuBase * 0.08, seed + 3)
  var mem = wave(n, memBase, 1.5, 18, seed, 0.4, seed + 5)
  var rx = spikes(n, netBase, netBase * 40, 11 + seed, seed + 9)
  var tx = spikes(n, netBase * 0.4, netBase * 9, 7 + seed, seed + 11)
  var memPercent = last(mem)
  return {
    status: status,
    info: { os: os, osName: osName, cores: cores },
    history: { cpuUser: user, cpuSys: sys, mem: mem, rx: rx, tx: tx },
    sample: {
      cpu: last(user) + last(sys), user: last(user), sys: last(sys),
      memUsed: total * memPercent / 100, memTotal: total, memPercent: memPercent,
      rx: last(rx), tx: last(tx), load: 1.2
    },
    reason: "",
    retryAt: 0
  }
}

var GB = 1024 * 1024 * 1024

function machines() {
  return [
    { id: "local", alias: "", host: "", enabled: true },
    { id: "studio-mini", alias: "studio-mini", host: "studio-mini", enabled: true },
    { id: "build-box", alias: "build-box", host: "builder@100.101.102.103", enabled: true },
    { id: "nas", alias: "nas", host: "nas.example-tailnet.ts.net", enabled: true },
    { id: "media-pc", alias: "media-pc", host: "media-pc.lan", enabled: false }
  ]
}

function manyMachines() {
  var list = machines()
  list.push({ id: "edge-1", alias: "edge-1", host: "edge-1", enabled: true })
  list.push({ id: "edge-2", alias: "edge-2", host: "edge-2", enabled: true })
  list.push({ id: "ci-runner", alias: "ci-runner", host: "ci@ci-runner", enabled: true })
  list.push({ id: "lab-pi", alias: "lab-pi", host: "pi@lab-pi.local", enabled: true })
  return list
}

function links(now) {
  return {
    "local": linkFor("online", "linux", "Arch Linux", 16, 32 * GB, 14, 58, 6000, 1),
    "studio-mini": linkFor("online", "macos", "macOS 15.4", 14, 64 * GB, 9, 62, 3000, 2),
    "build-box": linkFor("online", "linux", "Ubuntu 24.04", 32, 128 * GB, 71, 41, 90000, 3),
    "nas": { status: "offline", info: {}, history: null, sample: null, reason: "Connection timed out", retryAt: now + 8000 },
    "edge-1": linkFor("online", "linux", "Debian 12", 4, 8 * GB, 22, 47, 15000, 4),
    "edge-2": linkFor("stale", "linux", "Debian 12", 4, 8 * GB, 5, 33, 2000, 5),
    "ci-runner": { status: "connecting", info: {}, history: null, sample: null, reason: "", retryAt: 0 },
    "lab-pi": linkFor("online", "linux", "Raspberry Pi OS", 4, 4 * GB, 36, 71, 800, 6)
  }
}
