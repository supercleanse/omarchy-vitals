import QtQuick
import qs.Commons as Commons
import "../../Model.js" as Model
import "../../omastats/Model.js" as Oma
import "fixtures.js" as Fixtures

// Stands in for DetailSource in the offscreen harness: an OmaStats-shaped
// snapshot from fixtures.js and histories built from the fixture card.
QtObject {
  id: root

  property string os: "linux"
  property string tab: "cpu"
  property var link: null
  property var themeColors: ({})

  readonly property var snapshot: os === "macos" ? Fixtures.macDetail(tab) : Fixtures.linuxDetail(tab)
  readonly property bool ready: true
  readonly property string status: "online"
  readonly property var info: link && link.info ? link.info : ({})
  readonly property bool hasGpu: !!info.caps && info.caps.gpu === true
  readonly property bool hasBattery: !!info.caps && info.caps.battery === true
  readonly property var graphPalette: Oma.pickPalette(themeColors, Commons.Color.accent, Commons.Color.foreground, Commons.Color.background, Commons.Color.urgent)
  readonly property color series1: graphPalette.series1
  readonly property color series2: graphPalette.series2
  readonly property color tertiary: graphPalette.tertiary
  readonly property color warn: graphPalette.warn
  readonly property color danger: graphPalette.danger
  readonly property color good: graphPalette.good

  function requestPublicIp(force) {}

  readonly property var history: {
    var h = link && link.history ? link.history : null
    var out = Oma.emptyHistory()
    if (!h) return out
    var copy = function(a) { return Model.asArray(a) ? Model.asArray(a).slice() : [] }
    out.cpuUser = copy(h.cpuUser)
    out.cpuSystem = copy(h.cpuSys)
    out.memUsed = copy(h.mem)
    out.netRx = copy(h.rx)
    out.netTx = copy(h.tx)
    for (var g in (h.gpu || {})) out.gpus[g] = copy(h.gpu[g])
    for (var m in (h.gpuMem || {})) out.gpuMemory.gpus[m] = copy(h.gpuMem[m])
    out.diskRead = copy((h.diskRead || {}).all)
    out.diskWrite = copy((h.diskWrite || {}).all)
    for (var d in (h.diskRead || {})) if (d !== "all") out.disks[d] = { read: copy(h.diskRead[d]), write: copy(h.diskWrite[d]) }
    out.battery = copy(h.battery)
    out.batteryCharging = out.battery.map(function() { return 0 })
    return out
  }
}
