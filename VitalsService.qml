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
  // Defaults every machine follows until it has its own readout settings.
  readonly property var defaultModules: cfg.modules.length > 0 ? cfg.modules : ["cpu", "memory", "network"]
  readonly property string defaultStyle: cfg.style
  readonly property string labelMode: cfg.labels
  readonly property string temperatureUnit: cfg.temperatureUnit
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
    var next = {}
    for (var k in rawSettings) if (k !== "id") next[k] = rawSettings[k]
    next[key] = value
    // Apply at once; the saved entry comes back through the widget.
    lastSettings = next
    var keys = Object.keys(instanceSettings)
    if (keys.length > 0) {
      var inst = {}
      for (var i in instanceSettings) inst[i] = instanceSettings[i]
      inst[keys[keys.length - 1]] = next
      instanceSettings = inst
    }
    if (!shell || typeof shell.updateEntryInline !== "function") return false
    return shell.updateEntryInline(Model.PLUGIN_ID, next)
  }

  // ------------------------------------------------------------ paths

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/vitals"
  readonly property string configPath: configDir + "/machines.json"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/vitals"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string samplerPath: decodeURIComponent(String(Qt.resolvedUrl("sampler/vitals-sampler.sh")).replace(/^file:\/\//, ""))
  readonly property string detailPath: decodeURIComponent(String(Qt.resolvedUrl("sampler/vitals-detail.sh")).replace(/^file:\/\//, ""))
  // SSH control sockets live in a private runtime directory, so a detail
  // session rides the card session's connection instead of a new handshake.
  readonly property string controlDir: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/vitals-ssh" : ""

  // ------------------------------------------------------------ state

  property bool open: false
  property bool stateLoaded: false
  property bool editing: false
  property var editor: null
  // The machine whose readout settings are open, or "".
  property string settingsId: ""
  // The open detail panel: which machine and tab. It shares one slot with
  // the settings page, so at most one of the two is open.
  property string detailId: ""
  property string detailTab: "cpu"
  property bool detailAll: false
  // Where the clicked card sits in the sidebar, so the popout lines up with
  // it, and the sidebar's height, so it fits.
  property real popoutY: 0
  property real dockHeight: 0
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
    settingsId = ""
    detailId = ""
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

  function machineFor(id) {
    for (var i = 0; i < machines.length; i++) if (machines[i].id === id) return machines[i]
    return null
  }

  function openSettings(id) {
    if (!machineFor(id)) return "unknown machine"
    editor = null
    detailId = ""
    settingsId = id
    open = true
    return "ok"
  }

  function closeSettings() { settingsId = "" }

  function openDetail(id, tab, anchorY) {
    if (!machineFor(id)) return "unknown machine"
    editor = null
    settingsId = ""
    if (anchorY !== undefined && anchorY !== null) popoutY = anchorY
    var tabs = Model.detailTabs(linkFor(id) ? linkFor(id).info : null)
    var want = Model.tabFor(tab || "cpu")
    detailTab = tabs.indexOf(want) !== -1 ? want : (tabs[0] || "cpu")
    if (detailId !== id) detailAll = false
    detailId = id
    open = true
    return "ok"
  }

  // A readout click: open that machine on that tab, or close the panel when
  // the same readout is clicked again.
  function toggleDetail(id, module, anchorY) {
    if (detailId === id && detailTab === Model.tabFor(module)) { closeDetail(); return "ok" }
    return openDetail(id, module, anchorY)
  }

  function closeDetail() { detailId = ""; detailAll = false }

  function setDetailTab(tab) {
    if (tab === "settings") { var id = detailId; closeDetail(); openSettings(id); return }
    detailTab = Model.tabFor(tab)
  }

  // Readout settings for one machine, merged in and saved. A null value
  // returns that key to the default.
  function updateMachine(id, patch) {
    if (configError) return
    commitMachines(Model.updateMachine(machines, id, patch || {}))
  }

  function resetReadouts(id) {
    if (configError) return
    commitMachines(Model.resetReadouts(machines, id))
  }

  // Rename or re-point a machine from the settings page. Returns "" or an error.
  function renameMachine(id, alias, host) {
    var m = machineFor(id)
    if (!m) return "Unknown machine"
    return saveEditor({ id: id, alias: alias, host: host, enabled: m.enabled !== false })
  }

  // Global look settings, saved on the widget's entry in shell.json.
  function setGlobal(key, value) { persistSetting(key, value) }

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
    var text = Model.serializeMachines(list)
    // Mark it as read, so the reload our own write triggers is a no-op.
    configText = text
    configLoaded = true
    writeGuardUntil = Date.now() + 1500
    writeFile(configFile, text)
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
        tx: s ? s.tx : null,
        modules: Model.machineModules(m, defaultModules),
        caps: link && link.info ? link.info.caps : null,
        gpus: s ? s.gpus : null,
        disk: s && s.disk ? { read: s.disk.read, write: s.disk.write, space: s.disk.space.all || null } : null,
        temps: s ? s.temps : null,
        fans: s ? s.fans : null,
        battery: s ? s.battery : null
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
        samplerPath: root.samplerPath,
        controlDir: root.controlDir
      })
      if (!obj) continue
      obj.intervalSeconds = Qt.binding(function() { return root.intervalSeconds })
      obj.extras = Qt.binding((function(machineId) {
        return function() { return Model.samplerExtras(root.machineFor(machineId), root.defaultModules) }
      })(wid))
      obj.sensorIds = Qt.binding((function(link, machineId) {
        return function() { return Model.samplerSensorIds(root.machineFor(machineId), link.info) }
      })(obj, wid))
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

  // The last text read from or written to machines.json, to skip no-op reloads.
  property string configText: ""
  property bool configLoaded: false
  property int badReads: 0

  property real writeGuardUntil: 0

  function applyConfigText(text) {
    var raw = String(text || "")
    if (raw === configText && configLoaded) return
    // Just after our own write, a read can still return the old text.
    if (Date.now() < writeGuardUntil) return
    var parsed = Model.parseMachinesFile(raw)
    if (!parsed.ok) {
      // `cat > file` truncates before it writes, so a read can land on an
      // empty or half-written file. Look again shortly before calling it bad,
      // and never drop a good list for a bad read.
      if (badReads < 3) {
        badReads += 1
        rereadTimer.restart()
        return
      }
      configError = "~/.config/vitals/machines.json is not valid JSON. Fix or delete the file; until then nothing is saved to it."
      if (!configLoaded) machines = parsed.machines
      return
    }
    badReads = 0
    configError = ""
    configText = raw
    configLoaded = true
    if (JSON.stringify(machines) !== JSON.stringify(parsed.machines)) machines = parsed.machines
    if (parsed.version < Model.FILE_VERSION) migrateConfig(raw, parsed.machines)
  }

  // Version 1 files gain per-machine readout settings in version 2. The old
  // file is kept beside the new one as machines.v1.json.
  function migrateConfig(oldText, list) {
    writeFile(backupFile, oldText)
    commitMachines(list)
  }

  FileView {
    id: backupFile
    path: root.configDir + "/machines.v1.json"
    printErrors: false
    preload: false
  }

  // Coalesces the burst of change events one external write produces.
  Timer {
    id: changeTimer
    interval: 250
    repeat: false
    onTriggered: configFile.reload()
  }

  Timer {
    id: rereadTimer
    interval: 400
    repeat: false
    onTriggered: configFile.reload()
  }

  // A safety net for edits the file watch never reports (an editor that
  // replaces the file, a network home directory): look every few seconds.
  // Skipped while Vitals is writing the file itself.
  Timer {
    interval: 3000
    repeat: true
    running: root.configLoaded
    onTriggered: if (root.pendingWrites.length === 0 && !mkdirProc.running) configFile.reload()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConfigText(text())
    onFileChanged: changeTimer.restart()
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

  // The detail panel's data: running only while a panel is open.
  DetailSource {
    id: detailSource
    active: root.settingsReady && root.open && root.detailId !== "" && !!root.machineFor(root.detailId)
    machineId: root.detailId
    host: root.machineFor(root.detailId) ? root.machineFor(root.detailId).host : ""
    detailPath: root.detailPath
    controlDir: root.controlDir
    intervalSeconds: root.intervalSeconds
    historyLength: root.historyLength
    tab: root.detailTab
    allProcesses: root.detailAll
    link: root.linkFor(root.detailId)
    themeColors: root.themeColors
  }

  readonly property var detail: detailSource

  // One popout beside the dock for both the settings page and the detail
  // panel.
  LazyLoader {
    active: root.settingsReady && root.open && root.mode === "dock" && (root.settingsId !== "" || root.detailId !== "")
    source: Qt.resolvedUrl("ui/SidePopout.qml")
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
    function settings(id: string): string { return root.openSettings(id || "local") }
    function detail(id: string, tab: string): string { return root.openDetail(id || "local", tab || "cpu", null) }
    function status(): string { return JSON.stringify(root.summary()) }
  }
}
