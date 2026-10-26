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

  property bool many: false
  property real clock: 1000000
  property var machines: many ? Fixtures.manyMachines() : Fixtures.machines()
  property var links: Fixtures.links(clock)
  property int linksRevision: 0
  property string localHostname: "laptop"
  property bool editing: false
  property var editor: null
  property string configError: ""
  property bool open: true
  property bool sampling: true
  property int panelWidth: 200
  readonly property var enabledMachines: machines.filter(function(m) { return m.enabled !== false })
  property int onlineCount: 3
  property int offlineCount: sampling ? 1 : 0

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

  function linkFor(id) { return links[id] || null }
  function registerSettings(key, settings) {}
  function unregisterSettings(key) {}
  function setEditing(value) { editing = value === true }
  function openEditor(id) {
    if (!id) editor = { id: "", alias: "", host: "", enabled: true }
    else {
      var m = machines.filter(function(x) { return x.id === id })[0]
      editor = m ? { id: m.id, alias: m.alias, host: m.host, enabled: m.enabled } : null
    }
    editing = true
  }
  function closeEditor() { editor = null }
  function saveEditor(values) { return Model.validateHost(values.host) }
  function removeMachine(id) {}
  function moveMachine(id, delta) {}
  function setMachineEnabled(id, value) {}
  function refresh() {}
  function show() {}
  function hide() {}
  function toggle() {}
}
