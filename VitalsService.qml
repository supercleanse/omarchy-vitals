import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "Model.js" as Model

// The one Vitals instance per shell. It owns the machine list
// (~/.config/vitals/machines.json), one sampler link per enabled machine,
// the sidebar or window, and the IPC target. Bar widgets report their
// settings here and toggle the sidebar through it.
Item {
  id: root

  // Injected by the shell.
  property var shell: null
  property var manifest: null

  // ------------------------------------------------------------ settings

  property var instanceSettings: ({})
  // The last settings any widget reported. The service is keepLoaded, so it
  // outlives the widget across a plugin hot reload; keeping these means the
  // sidebar and its connections stay put while the widget is rebuilt.
  property var lastSettings: ({})
  readonly property var rawSettings: {
    var keys = Object.keys(instanceSettings)
    return keys.length > 0 ? instanceSettings[keys[keys.length - 1]] : lastSettings
  }
  readonly property var cfg: Model.resolveSettings(rawSettings)
  // Nothing opens or connects until a bar widget has reported its settings
  // once, so a window-mode user never sees the dock flash first.
  property bool settingsReady: false
  // Set by the dock/window IPC methods so the switch is instant, then
  // cleared once the saved setting comes back from shell.json.
  property string modeOverride: ""
  readonly property string mode: modeOverride || cfg.mode
  readonly property string edge: cfg.edge
  readonly property int panelWidth: cfg.width
  readonly property real intervalSeconds: cfg.refreshSeconds
  readonly property int historyLength: Model.historyLength(cfg.historySeconds, cfg.refreshSeconds)
  readonly property var targetScreen: {
    var name = cfg.screen
    if (!name) return null
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
    return null
  }

  function registerSettings(key, settings) {
    var next = {}
    for (var k in instanceSettings) next[k] = instanceSettings[k]
    next[String(key)] = settings || {}
    lastSettings = settings || {}
    instanceSettings = next
    settingsReady = true
    if (modeOverride && Model.resolveSettings(settings).mode === modeOverride) modeOverride = ""
  }

  function unregisterSettings(key) {
    var next = {}
    for (var k in instanceSettings) if (k !== String(key)) next[k] = instanceSettings[k]
    instanceSettings = next
  }

  // Write one setting into this plugin's bar entry in shell.json, keeping the
  // others, so the Setup page and the IPC agree on one value.
  function persistSetting(key, value) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false
    var next = {}
    for (var k in rawSettings) if (k !== "id") next[k] = rawSettings[k]
    next[key] = value
    return shell.updateEntryInline(Model.PLUGIN_ID, next)
  }

  // ------------------------------------------------------------ paths

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/vitals"
  readonly property string configPath: configDir + "/machines.json"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/vitals"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string samplerPath: decodeURIComponent(String(Qt.resolvedUrl("sampler/vitals-sampler.sh")).replace(/^file:\/\//, ""))

  // ------------------------------------------------------------ state

  property bool open: false
  property bool stateLoaded: false
  property bool editing: false
  property var editor: null
  property var machines: Model.normalizeMachines(null)
  property string configError: ""
  property real clock: Date.now()
  property var links: ({})
  property int linksRevision: 0
  property bool destroying: false
  property string etcHostname: ""

  readonly property bool sampling: settingsReady && (open || cfg.sampleWhileHidden)
  readonly property string localHostname: {
    var rev = linksRevision
    if (etcHostname) return etcHostname
    var local = links["local"]
    return local && local.info && local.info.host ? local.info.host : ""
  }

  function linkFor(id) {
    var rev = linksRevision
    return links[id] || null
  }

  // Bar readout aggregate.
  readonly property var enabledMachines: machines.filter(function(m) { return m.enabled !== false })
  property int onlineCount: 0
  property int offlineCount: 0

  function recount() {
    var online = 0, offline = 0
    for (var i = 0; i < enabledMachines.length; i++) {
      var link = links[enabledMachines[i].id]
      if (!link) continue
      if (link.status === "online" || link.status === "stale") online++
      else if (link.status === "offline") offline++
    }
    onlineCount = online
    offlineCount = offline
  }

  // ------------------------------------------------------------ palette

  property var themeColors: ({})
  readonly property var graphPalette: Model.pickPalette(themeColors, Commons.Color.accent, Commons.Color.background, Commons.Color.urgent)
  readonly property color series1: graphPalette.series1
  readonly property color series2: graphPalette.series2
  readonly property color good: graphPalette.good
  readonly property color warn: graphPalette.warn
  readonly property color danger: graphPalette.danger

  // ------------------------------------------------------------ actions

  function show() { open = true; return "ok" }
  function hide() {
    open = false
    editing = false
    editor = null
    return "ok"
  }
  function toggle() { return open ? hide() : show() }

  function setMode(next) {
    if (Model.resolveSettings({ mode: next }).mode !== next) return "unknown mode"
    modeOverride = next
    persistSetting("mode", next)
    open = true
    return "ok"
  }

  function refresh() {
    configFile.reload()
    for (var id in links) links[id].retryNow()
    return "ok"
  }

  function setEditing(value) {
    editing = value === true
    if (!editing) editor = null
  }

  function openEditor(id) {
    if (configError) return
    if (!id) {
      editor = { id: "", alias: "", host: "", enabled: true }
    } else {
      var at = machines.map(function(m) { return m.id }).indexOf(id)
      if (at === -1) return
      var m = machines[at]
      editor = { id: m.id, alias: m.alias, host: m.host, enabled: m.enabled !== false }
    }
    editing = true
  }

  function closeEditor() { editor = null }

  // Returns "" on success, or a message for the form.
  function saveEditor(values) {
    if (configError) return "Fix machines.json first"
    var result = Model.upsertMachine(machines, values || {})
    if (result.error) return result.error
    commitMachines(result.machines)
    editor = null
    return ""
  }

  function removeMachine(id) { if (!configError) commitMachines(Model.removeMachine(machines, id)) }
  function moveMachine(id, delta) { if (!configError) commitMachines(Model.moveMachine(machines, id, delta)) }
  function setMachineEnabled(id, value) { if (!configError) commitMachines(Model.setMachineEnabled(machines, id, value)) }

  function commitMachines(list) {
    machines = list
    writeFile(configFile, Model.serializeMachines(list))
  }

  function summary() {
    var out = []
    for (var i = 0; i < machines.length; i++) {
      var m = machines[i]
      var link = links[m.id]
      var s = link ? link.sample : null
      out.push({
        id: m.id,
        alias: Model.displayAlias(m, localHostname),
        host: m.host,
        enabled: m.enabled !== false,
        status: link ? link.status : "idle",
        reason: link ? link.reason : "",
        cpu: s ? s.cpu : null,
        memPercent: s ? Math.round(s.memPercent * 10) / 10 : null,
        rx: s ? s.rx : null,
        tx: s ? s.tx : null
      })
    }
    return { open: open, mode: mode, sampling: sampling, machines: out }
  }

  // ------------------------------------------------------------ links

  Component {
    id: linkComponent
    MachineLink { }
  }

  // Keep exactly one link per enabled machine. A changed destination gets a
  // fresh link; a rename or reorder leaves the connection alone.
  function syncLinks() {
    if (destroying) return
    var want = {}
    for (var i = 0; i < machines.length; i++) if (machines[i].enabled !== false) want[machines[i].id] = machines[i]
    var next = {}
    var changed = false
    for (var id in links) {
      var link = links[id]
      if (!want[id] || want[id].host !== link.host) {
        link.destroy()
        changed = true
        continue
      }
      next[id] = link
    }
    for (var wid in want) {
      if (next[wid]) continue
      var obj = linkComponent.createObject(root, {
        machineId: wid,
        host: want[wid].host,
        samplerPath: root.samplerPath
      })
      if (!obj) continue
      obj.intervalSeconds = Qt.binding(function() { return root.intervalSeconds })
      obj.historyLength = Qt.binding(function() { return root.historyLength })
      obj.statusChanged.connect(root.recount)
      obj.active = Qt.binding(function() { return root.sampling })
      next[wid] = obj
      changed = true
    }
    links = next
    if (changed) linksRevision++
    recount()
  }

  onMachinesChanged: syncLinks()
  onEnabledMachinesChanged: recount()

  // ------------------------------------------------------------ files

  // Writes go through `mkdir -p` first: on a first run neither directory
  // exists yet.
  property var pendingWrites: []

  function writeFile(view, text) {
    pendingWrites = pendingWrites.concat([{ view: view, text: text }])
    if (!mkdirProc.running) {
      mkdirProc.command = ["mkdir", "-p", root.configDir, root.stateDir]
      mkdirProc.running = true
    }
  }

  Process {
    id: mkdirProc
    onExited: {
      var jobs = root.pendingWrites
      root.pendingWrites = []
      for (var i = 0; i < jobs.length; i++) jobs[i].view.setText(jobs[i].text)
    }
  }

  function applyConfigText(text) {
    var parsed = Model.parseMachinesFile(text)
    if (!parsed.ok) {
      configError = "~/.config/vitals/machines.json is not valid JSON, so only this machine is shown. Fix or delete the file."
      // Never overwrite a file the user is in the middle of editing.
      if (JSON.stringify(machines) !== JSON.stringify(parsed.machines)) machines = parsed.machines
      return
    }
    configError = ""
    if (JSON.stringify(machines) !== JSON.stringify(parsed.machines)) machines = parsed.machines
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfigText(text())
    onFileChanged: reload()
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) {
        // First run: write the default list (just this machine).
        root.configError = ""
        root.commitMachines(Model.normalizeMachines(null))
      } else {
        root.configError = "~/.config/vitals/machines.json could not be read."
      }
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    onLoaded: {
      var data = null
      try { data = JSON.parse(text()) } catch (e) { data = null }
      root.open = !!(data && data.open === true)
      root.stateLoaded = true
    }
    onLoadFailed: root.stateLoaded = true
  }

  onOpenChanged: {
    if (!stateLoaded) return
    writeFile(stateFile, JSON.stringify({ open: open }) + "\n")
  }

  FileView {
    path: "/etc/hostname"
    printErrors: false
    onLoaded: root.etcHostname = Model.displayAlias({ id: "local", alias: "" }, text().trim())
  }

  // The theme's named colors pick the second graph hue, as in OmaStats.
  FileView {
    id: colorsFile
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.themeColors = Model.parseColorsToml(text())
    onFileChanged: reload()
    onLoadFailed: root.themeColors = ({})
  }

  Connections {
    target: Commons.Color
    function onAccentChanged() { colorsFile.reload() }
    function onBackgroundChanged() { colorsFile.reload() }
  }

  // Ticks the "retry in Ns" countdowns while something is on screen.
  Timer {
    interval: 1000
    repeat: true
    running: root.open
    onTriggered: root.clock = Date.now()
  }

  // ------------------------------------------------------------ windows

  // Loaded by path so the layer-shell type is only resolved when the dock is
  // actually shown.
  LazyLoader {
    active: root.settingsReady && root.open && root.mode === "dock"
    source: Qt.resolvedUrl("ui/DockWindow.qml")
    onItemChanged: if (item) item.service = root
  }

  LazyLoader {
    active: root.settingsReady && root.open && root.mode === "window"
    source: Qt.resolvedUrl("ui/AppWindow.qml")
    onItemChanged: if (item) item.service = root
  }

  Component.onCompleted: syncLinks()

  Component.onDestruction: {
    destroying = true
    for (var id in links) links[id].destroy()
  }

  IpcHandler {
    target: "supercleanse.vitals"

    // `show` is avoided: the qs CLI parses it as its own subcommand.
    function toggle(): string { return root.toggle() }
    function open(): string { return root.show() }
    function close(): string { return root.hide() }
    function hide(): string { return root.hide() }
    function dock(): string { return root.setMode("dock") }
    function window(): string { return root.setMode("window") }
    function refresh(): string { return root.refresh() }
    function edit(): string { root.setEditing(true); return root.show() }
    function status(): string { return JSON.stringify(root.summary()) }
  }
}
