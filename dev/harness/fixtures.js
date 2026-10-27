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

// ---------------------------------------------------------------- detail
//
// Detail panel snapshots in OmaStats' schema, for the fictional laptop
// (Linux) and studio-mini (macOS desktop). Addresses come from the
// documentation ranges (192.0.2.0/24, 2001:db8::/32).

function proc(name, pid, count, cpu, mem, read, write) {
  return { name: name, pid: pid, count: count, cpu: cpu, mem: mem, read: read || 0, write: write || 0 }
}

var LINUX_PROCS = [
  proc("firefox", 4211, 14, 18.4, 2.9 * GB), proc("code", 5120, 9, 11.2, 1.6 * GB), proc("node", 6342, 3, 7.9, 0.61 * GB),
  proc("Xwayland", 1880, 1, 3.1, 0.18 * GB), proc("pipewire", 1702, 2, 1.4, 0.04 * GB), proc("postgres", 980, 7, 1.1, 0.33 * GB),
  proc("Hyprland", 1650, 1, 0.9, 0.21 * GB), proc("quickshell", 1990, 1, 0.6, 0.27 * GB)
]
var MAC_PROCS = [
  proc("Xcode", 812, 1, 22.7, 3.4 * GB), proc("WindowServer", 404, 1, 9.6, 0.61 * GB), proc("Safari", 1210, 6, 6.2, 1.9 * GB),
  proc("Docker", 1533, 4, 3.8, 2.2 * GB), proc("Music", 1602, 1, 1.2, 0.29 * GB), proc("Finder", 690, 1, 0.4, 0.15 * GB),
  proc("Mail", 1312, 1, 0.3, 0.33 * GB), proc("Terminal", 1450, 1, 0.3, 0.09 * GB)
]

function sortBy(list, key) { return list.slice().sort(function(a, b) { return b[key] - a[key] }) }

function linuxDetail(tab) {
  var cores = []
  for (var i = 0; i < 16; i++) cores.push(i < 4 ? 18 + i * 6 : 4 + (i * 7) % 15)
  var snap = {
    type: "detail", tab: tab,
    cpu: { user: 10.2, system: 3.8, iowait: 0.4, total: 14.0, load: [1.12, 0.94, 0.88], uptime: 302400,
      model: "AMD Ryzen 7 7840U w/ Radeon 780M Graphics", coreCount: 8, threadCount: 16,
      cores: cores, efficiency: [], mhz: 3120, maxMhz: 5100, temp: 52.5 },
    mem: { total: 32 * GB, used: 18.6 * GB, available: 13.4 * GB, free: 3.1 * GB, cached: 9.2 * GB, shared: 0.9 * GB,
      apps: 16.8 * GB, swapTotal: 8 * GB, swapUsed: 0.6 * GB, compressed: 1.4 * GB, compressedSize: 0.5 * GB,
      pressureSome: 0.4, pressureFull: 0.1 },
    net: { rx: 412000, tx: 38000 }
  }
  if (tab === "cpu" || tab === "memory") snap.procs = { total: 214, cpu: sortBy(LINUX_PROCS, "cpu"), mem: sortBy(LINUX_PROCS, "mem") }
  if (tab === "network") {
    snap.net.ifaces = [
      { name: "wlan0", up: true, wireless: true, default: true, ipv4: ["192.0.2.24"], ipv6: ["2001:db8::24"], rx: 412000, tx: 38000,
        rxTotal: 182 * GB, txTotal: 21 * GB, speed: 0, dbm: -54, ssid: "HomeNet" },
      { name: "tailscale0", up: true, wireless: false, default: false, ipv4: ["100.64.0.7"], ipv6: [], rx: 2200, tx: 900,
        rxTotal: 1.2 * GB, txTotal: 0.4 * GB, speed: 0 }
    ]
    snap.net.default = "wlan0"; snap.net.online = true
    snap.net.procs = [
      { name: "firefox", pid: 4211, count: 1, connections: 23, rx: 351000, tx: 22000 },
      { name: "code", pid: 5120, count: 1, connections: 6, rx: 41000, tx: 9800 },
      { name: "ssh", pid: 7012, count: 1, connections: 2, rx: 12000, tx: 4100 },
      { name: "syncthing", pid: 1410, count: 1, connections: 4, rx: 6100, tx: 1900 }
    ]
  }
  if (tab === "disks") {
    snap.disks = { read: 1850000, write: 620000, pressureSome: 0.3, pressureFull: 0.1,
      perDisk: { nvme0n1: { read: 1850000, write: 620000, busy: 6.5, id: "nvme0n1" } },
      volumes: [
        { device: "/dev/mapper/root", mount: "/", fstype: "btrfs", size: 1000 * GB, used: 412 * GB, avail: 588 * GB, disk: "nvme0n1", key: "nvme0n1", model: "Samsung SSD 990 PRO 1TB", rotational: false, removable: false, kind: "internal" },
        { device: "/dev/nvme0n1p1", mount: "/boot", fstype: "vfat", size: 2 * GB, used: 0.12 * GB, avail: 1.88 * GB, disk: "nvme0n1", key: "nvme0n1", model: "Samsung SSD 990 PRO 1TB", rotational: false, removable: false, kind: "internal" }
      ] }
    snap.procs = { total: 61, io: [proc("firefox", 4211, 14, 0, 0, 1210000, 402000), proc("code", 5120, 9, 0, 0, 380000, 160000), proc("node", 6342, 3, 0, 0, 120000, 41000)] }
  }
  if (tab === "sensors") {
    snap.cpuTemp = 52.5
    snap.sensors = { gpuTemp: 51,
      temps: [
        { chip: "CPU", id: "k10temp/temp1", label: "Tctl", max: 100, value: 52.5 },
        { chip: "GPU", id: "amdgpu/temp1", label: "edge", max: 100, value: 51 },
        { chip: "NVMe", id: "nvme/temp1", label: "Composite", max: 82.8, value: 39.8 },
        { chip: "Wi-Fi", id: "iwlwifi_1/temp1", label: "temp1", max: 0, value: 44 },
        { chip: "ACPI", id: "acpitz/temp1", label: "temp1", max: 105, value: 47 },
        { chip: "Battery", id: "BAT0/temp1", label: "temp", max: 0, value: 31.5 }
      ],
      fans: [{ chip: "ThinkPad", id: "thinkpad/fan1", label: "fan1", rpm: 2650 }] }
  }
  if (tab === "battery") {
    snap.battery = { present: true, percent: 76, status: "Discharging", timeToEmpty: 214, timeToFull: 0,
      energyNow: 39.6, energyFull: 52.1, energyDesign: 57.0, power: 11.1, voltage: 16.12, cycles: 212, health: 91.4,
      acOnline: false, model: "5B10W51829", technology: "Li-poly",
      peripherals: [{ name: "Wireless Mouse", percent: 70, status: "Discharging" }] }
  }
  if (tab === "gpu") {
    var g = { id: "0000:03:00.0", name: "AMD GPU", vendor: "amd", integrated: true, util: 22, mhz: 1450, maxMhz: 2700,
      temp: 51, power: 9, fan: null, memUsed: 2.5 * GB, memTotal: 8 * GB }
    snap.gpus = [g]; snap.gpu = g
  }
  return snap
}

function macDetail(tab) {
  var snap = {
    type: "detail", tab: tab,
    cpu: { user: 6.0, system: 3.0, total: 9.0, load: [2.41, 2.12, 1.98], uptime: 864000,
      model: "Apple M4 Pro", coreCount: 14, threadCount: 14 },
    mem: { total: 64 * GB, used: 39.5 * GB, apps: 33.7 * GB, cached: 18.2 * GB, free: 6.1 * GB,
      compressed: 5.8 * GB, compressedSize: 2.1 * GB, swapTotal: 2 * GB, swapUsed: 0.4 * GB },
    net: { rx: 128000, tx: 21000 }
  }
  if (tab === "cpu" || tab === "memory") snap.procs = { total: 486, cpu: sortBy(MAC_PROCS, "cpu"), mem: sortBy(MAC_PROCS, "mem") }
  if (tab === "network") {
    snap.net.ifaces = [
      { name: "en0", up: true, wireless: false, default: true, ipv4: ["192.0.2.41"], ipv6: ["2001:db8::41"], rx: 128000, tx: 21000, rxTotal: 911 * GB, txTotal: 288 * GB, speed: 0 },
      { name: "utun4", up: true, wireless: false, default: false, ipv4: ["100.64.0.12"], ipv6: [], rx: 900, tx: 500, rxTotal: 3.1 * GB, txTotal: 1.2 * GB, speed: 0 }
    ]
    snap.net.default = "en0"; snap.net.online = true; snap.net.procsAllProtocols = true
    snap.net.procs = [
      { name: "Safari", pid: 1210, count: 6, rx: 98000, tx: 9100 },
      { name: "Docker", pid: 1533, count: 4, rx: 21000, tx: 8800 },
      { name: "mDNSResponder", pid: 411, count: 1, rx: 1200, tx: 600 }
    ]
  }
  if (tab === "disks") {
    snap.disks = { read: 2100000, write: 410000, perDisk: {},
      volumes: [{ device: "/dev/disk3s1s1", mount: "/", size: 994 * GB, used: 295 * GB, avail: 699 * GB, disk: "disk3", key: "disk3", rotational: false, removable: false, kind: "internal" }] }
  }
  if (tab === "gpu") {
    var g = { id: "apple", name: "Apple M4 Pro GPU", vendor: "apple", integrated: true, util: 18, mhz: null, maxMhz: null,
      temp: null, power: null, fan: null, memUsed: 3.2 * GB, memTotal: null }
    snap.gpus = [g]; snap.gpu = g
  }
  return snap
}
