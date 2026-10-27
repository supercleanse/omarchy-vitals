import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "../../Model.js" as Model
import "fixtures.js" as Fixtures

// Stands in for VitalsService in the offscreen harness: the same properties
// and functions the views read, filled from fixtures.js. Used only by
// dev/render.sh, which refuses to run without --fake-data.
QtObject {
  id: root

  property string set: "default"
  property real clock: 1000000
  property var machines: set === "many" ? Fixtures.manyMachines()
    : (set === "looks" ? Fixtures.lookMachines() : (set === "mac" ? Fixtures.macDesktop() : Fixtures.machines()))
  property var links: Fixtures.links(clock)
  property int linksRevision: 0
  property string localHostname: "laptop"
  property bool editing: false
  property var editor: null
  property string settingsId: ""
  property string detailId: ""
  property string detailTab: "cpu"
  property bool detailAll: false
  property real popoutY: 0
  property real dockHeight: 0
  readonly property string detailOs: detailId === "studio-mini" ? "macos" : "linux"
  property FakeDetail detail: FakeDetail {
    os: root.detailOs
    tab: root.detailTab
    link: root.linkFor(root.detailId)
    themeColors: root.themeColors
  }
  property string configError: ""
  property bool open: true
  property bool sampling: true
  property int panelWidth: 200
  property string edge: "right"
  readonly property var enabledMachines: machines.filter(function(m) { return m.enabled !== false })
  property int onlineCount: 3
  property int offlineCount: sampling ? 1 : 0
  property var defaultModules: ["cpu", "memory", "network"]
  property string defaultStyle: "both"
  property string labelMode: "text"
  property string temperatureUnit: "Celsius"

  property var themeColors: ({})
  readonly property var graphPalette: Model.pickPalette(themeColors, Commons.Color.accent, Commons.Color.background, Commons.Color.urgent)
  readonly property color series1: graphPalette.series1
  readonly property color series2: graphPalette.series2
  readonly property color good: graphPalette.good
  readonly property color warn: graphPalette.warn
  readonly property color danger: graphPalette.danger

  property FileView colorsFile: FileView {
    path: Commons.Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.themeColors = Model.parseColorsToml(text())
  }

  function linkFor(id) {
    var l = links[id] || null
    // The macOS desktop scene shows studio-mini as the Mac it is.
    if (set === "mac" && id === "studio-mini") return links["studio-mini"]
    return l
  }
  function machineFor(id) {
    for (var i = 0; i < machines.length; i++) if (machines[i].id === id) return machines[i]
    return null
  }
  function registerSettings(key, settings) {}
  function unregisterSettings(key) {}
  function setEditing(value) { editing = value === true }
  function openEditor(id) {
    if (!id) editor = { id: "", alias: "", host: "", enabled: true }
    else {
      var m = machineFor(id)
      editor = m ? { id: m.id, alias: m.alias, host: m.host, enabled: m.enabled } : null
    }
    editing = true
  }
  function closeEditor() { editor = null }
  function saveEditor(values) { return Model.validateHost(values.host) }
  function openSettings(id) { settingsId = id; detailId = "" }
  function openDetail(id, tab, y) { detailId = id; detailTab = Model.tabFor(tab); settingsId = "" }
  function toggleDetail(id, module, y) { if (detailId === id && detailTab === Model.tabFor(module)) detailId = ""; else openDetail(id, module, y) }
  function closeDetail() { detailId = "" }
  function setDetailTab(tab) { if (tab === "settings") openSettings(detailId); else detailTab = tab }
  function closeSettings() { settingsId = "" }
  function updateMachine(id, patch) { machines = Model.updateMachine(machines, id, patch) }
  function resetReadouts(id) { machines = Model.resetReadouts(machines, id) }
  function renameMachine(id, alias, host) { return "" }
  function setGlobal(key, value) {}
  function removeMachine(id) {}
  function moveMachine(id, delta) {}
  function setMachineEnabled(id, value) {}
  function refresh() {}
  function show() {}
  function hide() {}
  function toggle() {}
}
