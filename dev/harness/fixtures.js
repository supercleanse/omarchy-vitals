.pragma library

// Fictional machines and synthetic histories for the offscreen harness only.
// Nothing here is read by the plugin itself.

var GB = 1024 * 1024 * 1024
var N = 60

function wave(base, amp, period, phase, jitter, seed) {
  var out = []
  var s = seed || 1
  for (var i = 0; i < N; i++) {
    s = (s * 9301 + 49297) % 233280
    var noise = (s / 233280 - 0.5) * 2 * (jitter || 0)
    out.push(Math.max(0, base + amp * Math.sin((i + phase) / period) + noise))
  }
  return out
}

function spikes(base, peak, every, seed) {
  var out = []
  var s = seed || 7
  for (var i = 0; i < N; i++) {
    s = (s * 9301 + 49297) % 233280
    var r = s / 233280
    out.push(i % every < 3 ? peak * (0.4 + r * 0.6) : base * (0.3 + r))
  }
  return out
}

function last(list) { return list[list.length - 1] }

// One online machine. `extra` adds gpus/disks/sensors/battery to the sample
// and the hello info.
function online(o) {
  var seed = o.seed
  var user = wave(o.cpu * 0.7, o.cpu * 0.35, 6, seed, o.cpu * 0.2, seed)
  var sys = wave(o.cpu * 0.3, o.cpu * 0.12, 4, seed * 2, o.cpu * 0.08, seed + 3)
  var mem = wave(o.mem, 1.5, 18, seed, 0.4, seed + 5)
  var rx = spikes(o.net, o.net * 40, 11 + seed, seed + 9)
  var tx = spikes(o.net * 0.4, o.net * 9, 7 + seed, seed + 11)
  var info = {
    os: o.os, osName: o.osName, cores: o.cores,
    caps: { gpu: !!o.gpus, disks: true, sensors: !!o.sensors, battery: !!o.battery },
    gpus: (o.gpus || []).map(function(g) { return { id: g.id, name: g.name, vendor: g.vendor, util: g.util !== null } }),
    disks: o.disks || [],
    sensors: o.sensors || [],
    sensorsNote: ""
  }
  var history = { cpuUser: user, cpuSys: sys, mem: mem, rx: rx, tx: tx, gpu: {}, gpuMem: {}, diskRead: {}, diskWrite: {}, battery: [] }
  var sample = {
    cpu: last(user) + last(sys), user: last(user), sys: last(sys),
    memUsed: o.total * last(mem) / 100, memTotal: o.total, memPercent: last(mem),
    rx: last(rx), tx: last(tx), load: o.load || 1.2,
    gpus: null, disk: null, temps: null, fans: null, battery: null
  }
  if (o.gpus) {
    sample.gpus = []
    for (var g = 0; g < o.gpus.length; g++) {
      var gp = o.gpus[g]
      var util = gp.util === null ? null : wave(gp.util, gp.util * 0.4, 5, seed + g, gp.util * 0.2, seed + 13 + g)
      if (util) history.gpu[gp.id] = util
      var vram = gp.memTotal ? wave(gp.vram, 3, 20, seed, 0.5, seed + 17) : null
      if (vram) history.gpuMem[gp.id] = vram
      sample.gpus.push({ id: gp.id, util: util ? last(util) : null, mhz: gp.mhz || null, temp: gp.temp || null,
        memUsed: vram ? gp.memTotal * last(vram) / 100 : (gp.memUsed || null), memTotal: gp.memTotal || null })
    }
  }
  if (o.space) {
    var dr = spikes(o.diskRate, o.diskRate * 30, 9 + seed, seed + 21)
    var dw = spikes(o.diskRate * 0.6, o.diskRate * 12, 13 + seed, seed + 23)
    history.diskRead.all = dr
    history.diskWrite.all = dw
    var per = {}
    var space = { all: o.space }
    for (var d = 0; d < (o.disks || []).length; d++) {
      history.diskRead[o.disks[d]] = dr
      history.diskWrite[o.disks[d]] = dw
      per[o.disks[d]] = [last(dr), last(dw)]
      space[o.disks[d]] = o.space
    }
    sample.disk = { read: last(dr), write: last(dw), per: per, space: space }
  }
  if (o.temps) { sample.temps = o.temps; sample.fans = o.fans || {} }
  if (o.battery) {
    history.battery = wave(o.battery.percent, 2, 30, seed, 0.2, seed + 29)
    sample.battery = o.battery
  }
  return { status: o.status || "online", info: info, history: history, sample: sample, reason: "", retryAt: 0 }
}

function offline(reason, now) {
  return { status: "offline", info: {}, history: null, sample: null, reason: reason, retryAt: now + 8000 }
}

var LINUX_SENSORS = [
  { id: "cpu", label: "CPU temperature", kind: "temp" },
  { id: "amdgpu/temp1", label: "GPU edge", kind: "temp" },
  { id: "nvme/temp1", label: "NVMe Composite", kind: "temp" },
  { id: "acpitz/temp1", label: "ACPI temp1", kind: "temp" },
  { id: "thinkpad/fan1", label: "ThinkPad fan1", kind: "fan" }
]

function machines() {
  return [
    { id: "local", alias: "", host: "", enabled: true,
      modules: ["cpu", "gpu", "memory", "disks", "network", "sensors", "battery"],
      sensors: ["cpu", "nvme/temp1", "thinkpad/fan1"] },
    { id: "studio-mini", alias: "studio-mini", host: "studio-mini", enabled: true,
      modules: ["cpu", "memory", "gpu", "network"] },
    { id: "build-box", alias: "build-box", host: "builder@100.101.102.103", enabled: true,
      modules: ["cpu", "memory", "disks", "network"], styles: { cpu: "ring-text", memory: "ring-text" },
      disks: [{ disk: "all", show: "used" }] },
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

// Five copies of one machine, each set to a different look, for the looks scene.
function lookMachines() {
  var looks = ["both", "graph", "text", "ring-text", "ring"]
  return looks.map(function(look) {
    var styles = {}
    var mods = ["cpu", "gpu", "memory", "disks", "network", "sensors", "battery"]
    for (var i = 0; i < mods.length; i++) styles[mods[i]] = look
    return { id: "look-" + look, alias: look, host: "laptop-" + look, enabled: true, modules: mods, styles: styles,
      disks: [{ disk: "all", show: "both" }], sensors: ["cpu", "nvme/temp1", "thinkpad/fan1"] }
  })
}

function links(now) {
  var laptop = online({
    seed: 1, os: "linux", osName: "Arch Linux", cores: 16, total: 32 * GB, cpu: 14, mem: 58, net: 6000,
    gpus: [{ id: "0000:03:00.0", name: "AMD GPU", vendor: "amd", util: 22, temp: 51, mhz: 1450, vram: 31, memTotal: 8 * GB }],
    disks: ["nvme0n1"], space: [412 * GB, 1000 * GB], diskRate: 80000,
    sensors: LINUX_SENSORS, temps: { cpu: 52.5, "nvme/temp1": 39.8, "amdgpu/temp1": 51 }, fans: { "thinkpad/fan1": 2650 },
    battery: { percent: 76, status: "Discharging", toEmpty: 214, toFull: null }
  })
  var studio = online({
    seed: 2, os: "macos", osName: "macOS 15.4", cores: 14, total: 64 * GB, cpu: 9, mem: 62, net: 3000,
    gpus: [{ id: "apple", name: "Apple M4 Pro GPU", vendor: "apple", util: 18, memUsed: 3 * GB }],
    space: [295 * GB, 994 * GB], diskRate: 40000
  })
  var build = online({
    seed: 3, os: "linux", osName: "Ubuntu 24.04", cores: 32, total: 128 * GB, cpu: 71, mem: 41, net: 90000,
    disks: ["nvme0n1", "sda"], space: [1730 * GB, 3700 * GB], diskRate: 900000
  })
  var all = {
    "local": laptop,
    "studio-mini": studio,
    "build-box": build,
    "nas": offline("Connection timed out", now),
    "edge-1": online({ seed: 4, os: "linux", osName: "Debian 12", cores: 4, total: 8 * GB, cpu: 22, mem: 47, net: 15000 }),
    "edge-2": online({ seed: 5, os: "linux", osName: "Debian 12", cores: 4, total: 8 * GB, cpu: 5, mem: 33, net: 2000, status: "stale" }),
    "ci-runner": { status: "connecting", info: {}, history: null, sample: null, reason: "", retryAt: 0 },
    "lab-pi": online({ seed: 6, os: "linux", osName: "Raspberry Pi OS", cores: 4, total: 4 * GB, cpu: 36, mem: 71, net: 800 })
  }
  var looks = ["both", "graph", "text", "ring-text", "ring"]
  for (var i = 0; i < looks.length; i++) all["look-" + looks[i]] = laptop
  return all
}

// A desktop Mac for the macOS settings scene: no battery, no sensors.
function macDesktop() {
  return [
    { id: "local", alias: "", host: "", enabled: true },
    { id: "studio-mini", alias: "studio-mini", host: "studio-mini", enabled: true, modules: ["cpu", "memory", "gpu", "network"] }
  ]
}
