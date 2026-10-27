import QtQuick
import Quickshell.Io
import qs.Commons as Commons
import "Model.js" as Model
import "omastats/Model.js" as Oma

// What one detail panel reads: the detail sampler for one machine and one
// tab, presented the way OmaStats' service presents its sampler, so the
// OmaStats panel pages draw it unchanged. It runs only while a panel is open,
// restarts when the tab or the process list level changes, and stops when
// the panel closes.
//
// Histories start from the machine card's own, so graphs are full the moment
// the panel opens, then grow with each detail sample.
Item {
  id: root

  property string machineId: ""
  property string host: ""
  property string detailPath: ""
  property string controlDir: ""
  property real intervalSeconds: 2
  property int historyLength: 60
  property string tab: "cpu"
  property bool allProcesses: false
  property bool active: false
  // The machine's card link: its history seeds ours, its info gives the
  // capabilities.
  property var link: null
  property var themeColors: ({})

  property var snapshot: ({})
  property var history: Oma.emptyHistory()
  property bool ready: false
  property string status: "idle"
  property string reason: ""
  property int attempts: 0
  property bool destroying: false
  property bool stopping: false
  property bool restartPending: false
  property bool renewing: false

  readonly property var info: link && link.info ? link.info : ({})
  readonly property var command: Model.detailCommand(detailPath, host, intervalSeconds, tab, allProcesses, controlDir)

  // The palette and flags OmaStats' pages read off their service.
  readonly property var graphPalette: Oma.pickPalette(themeColors, Commons.Color.accent, Commons.Color.foreground, Commons.Color.background, Commons.Color.urgent)
  readonly property color series1: graphPalette.series1
  readonly property color series2: graphPalette.series2
  readonly property color tertiary: graphPalette.tertiary
  readonly property color warn: graphPalette.warn
  readonly property color danger: graphPalette.danger
  readonly property color good: graphPalette.good
  readonly property bool hasGpu: Model.moduleAvailable("gpu", info) && !!info.caps
  readonly property bool hasBattery: Model.moduleAvailable("battery", info) && !!info.caps

  // OmaStats looks its public address up from api.ipify.org. Vitals never
  // does: for a remote machine that would mean a web request from that
  // machine, so the Network page's public IP card stays hidden.
  function requestPublicIp(force) {}

  function seedHistory() {
    var h = link && link.history ? link.history : null
    var out = Oma.emptyHistory()
    if (h) {
      var copy = function(a) { return Model.asArray(a) ? Model.asArray(a).slice() : [] }
      out.cpuUser = copy(h.cpuUser)
      out.cpuSystem = copy(h.cpuSys)
      out.cpuTotal = out.cpuUser.map(function(v, i) { return v + (out.cpuSystem[i] || 0) })
      out.memUsed = copy(h.mem)
      out.netRx = copy(h.rx)
      out.netTx = copy(h.tx)
      for (var g in (h.gpu || {})) out.gpus[g] = copy(h.gpu[g])
      for (var m in (h.gpuMem || {})) out.gpuMemory.gpus[m] = copy(h.gpuMem[m])
      var reads = h.diskRead || {}, writes = h.diskWrite || {}
      out.diskRead = copy(reads.all)
      out.diskWrite = copy(writes.all)
      for (var d in reads) if (d !== "all") out.disks[d] = { read: copy(reads[d]), write: copy(writes[d]) }
      out.battery = copy(h.battery)
    }
    history = out
  }

  // OmaStats' own ingest, trimmed to the fields the detail sampler sends.
  function ingest(line) {
    var text = String(line || "")
    if (!text || text.length > 1048576 || text.charAt(0) !== "{") return
    var data
    try { data = JSON.parse(text) } catch (e) { return }
    if (!data || typeof data !== "object") return
    if (data.type === "error") { reason = String(data.message || ""); return }
    if (data.type === "renew") { renewing = true; return }
    if (data.type !== "detail") return
    var h = history
    var n = historyLength
    var cpu = data.cpu || {}
    var mem = data.mem || {}
    var net = data.net || {}
    var memPercent = mem.total > 0 ? mem.used / mem.total * 100 : null
    var next = {
      cpuUser: Oma.pushHistory(h.cpuUser, cpu.user, n),
      cpuSystem: Oma.pushHistory(h.cpuSystem, cpu.system, n),
      cpuTotal: Oma.pushNullableHistory(h.cpuTotal, cpu.total, n),
      gpu: h.gpu, gpus: h.gpus, gpuMemory: h.gpuMemory,
      memUsed: Oma.pushNullableHistory(h.memUsed, memPercent, n),
      memPressure: Oma.pushHistory(h.memPressure, mem.pressureSome, n),
      netRx: Oma.pushHistory(h.netRx, net.rx, n),
      netTx: Oma.pushHistory(h.netTx, net.tx, n),
      diskRead: h.diskRead, diskWrite: h.diskWrite, disks: h.disks,
      battery: h.battery, batteryCharging: h.batteryCharging
    }
    if (Array.isArray(data.gpus)) {
      var gpus = {}, gmem = {}
      for (var gi = 0; gi < data.gpus.length; gi++) {
        var key = Oma.gpuId(data.gpus[gi]) || String(gi)
        gpus[key] = Oma.pushNullableHistory(h.gpus[key], Oma.gpuHasUtil(data.gpus[gi]) ? data.gpus[gi].util : null, n)
        gmem[key] = Oma.pushNullableHistory(h.gpuMemory.gpus ? h.gpuMemory.gpus[key] : [], Oma.gpuMemoryPercent(data.gpus[gi]), n)
      }
      next.gpus = gpus
      next.gpuMemory = { gpu: gmem[Object.keys(gmem)[0]] || [], gpus: gmem }
      next.gpu = gpus[Object.keys(gpus)[0]] || []
    }
    if (data.disks) {
      next.diskRead = Oma.pushHistory(h.diskRead, data.disks.read, n)
      next.diskWrite = Oma.pushHistory(h.diskWrite, data.disks.write, n)
      var per = data.disks.perDisk || {}
      var disks = {}
      for (var name in per) {
        var prev = h.disks && h.disks[name] ? h.disks[name] : { read: [], write: [] }
        disks[name] = { read: Oma.pushHistory(prev.read, per[name].read, n), write: Oma.pushHistory(prev.write, per[name].write, n) }
      }
      next.disks = disks
    }
    if (data.battery && data.battery.present) {
      next.battery = Oma.pushHistory(h.battery, data.battery.percent, n)
      next.batteryCharging = Oma.pushHistory(h.batteryCharging, data.battery.status === "Charging" ? 1 : 0, n)
    }
    // OmaStats' Sensors page reads the CPU temperature off cpu.temp.
    if (data.cpuTemp !== undefined && data.cpu) data.cpu.temp = data.cpuTemp
    history = next
    snapshot = data
    ready = true
    status = "online"
    reason = ""
    attempts = 0
  }

  function start() {
    if (destroying || !active || !detailPath || !machineId) return
    retryTimer.stop()
    if (proc.running) return
    stopping = false
    proc.command = command
    proc.running = true
  }

  function stop() {
    retryTimer.stop()
    if (proc.running) { stopping = true; proc.running = false }
    status = "idle"
  }

  function restart() {
    retryTimer.stop()
    if (proc.running) {
      restartPending = true
      stopping = true
      proc.running = false
    } else {
      start()
    }
  }

  function reset() {
    ready = false
    snapshot = ({})
    reason = ""
    attempts = 0
    seedHistory()
  }

  onActiveChanged: {
    if (active) { reset(); status = "connecting"; start() }
    else stop()
  }
  onMachineIdChanged: if (active) { reset(); status = "connecting"; restart() }
  // A new tab keeps the history; until its first sample the panel says it
  // is collecting rather than showing the last tab's data.
  onTabChanged: ready = false
  onCommandChanged: if (active && proc.running) restart()

  Component.onDestruction: {
    destroying = true
    retryTimer.stop()
    if (proc.running) proc.running = false
  }

  Process {
    id: proc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.ingest(line) }
    }
    stderr: SplitParser {
      onRead: function(line) {
        if (root.stopping) return
        var why = Model.sshReason(line)
        if (why) root.reason = why
      }
    }
    onExited: function(code, exitStatus) {
      root.stopping = false
      if (root.destroying) return
      if (root.restartPending || root.renewing) {
        root.restartPending = false
        root.renewing = false
        root.start()
        return
      }
      if (!root.active) { root.status = "idle"; return }
      root.status = "offline"
      root.attempts += 1
      retryTimer.interval = Model.backoffMs(root.attempts)
      retryTimer.restart()
    }
  }

  Timer {
    id: retryTimer
    repeat: false
    onTriggered: root.start()
  }
}
