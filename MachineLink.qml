import QtQuick
import Quickshell.Io
import "Model.js" as Model

// One machine's sampler connection. Local machines run the sampler under sh;
// remote ones stream it to `sh -s` over ssh. The link keeps the latest
// sample and a rolling history, reconnects with backoff when the process
// exits, and marks the machine stale when samples stop arriving.
//
// status: "idle" (not sampling), "connecting", "online", "stale", "offline".
Item {
  id: root

  property string machineId: ""
  property string host: ""
  property string samplerPath: ""
  property real intervalSeconds: 2
  property int historyLength: 60
  property bool active: false

  readonly property bool isLocal: host === ""

  property string status: "idle"
  property var info: ({})
  property var sample: null
  property var history: Model.emptyHistory()
  property string reason: ""
  property int attempts: 0
  property real lastSeen: 0
  property real retryAt: 0
  property bool destroying: false

  readonly property bool hasData: sample !== null
  readonly property var command: isLocal
    ? Model.localCommand(samplerPath, intervalSeconds)
    : Model.remoteCommand(samplerPath, host, intervalSeconds)

  function start() {
    if (destroying || !active || !samplerPath) return
    retryTimer.stop()
    if (proc.running) return
    // A retry after a failure keeps showing "offline · reconnecting" and
    // its reason; a fresh start clears both.
    if (attempts === 0) { status = "connecting"; reason = "" }
    stopping = false
    startedAt = Date.now()
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
    attempts = 0
    if (proc.running) {
      restartPending = true
      stopping = true
      proc.running = false
    } else {
      start()
    }
  }

  // Skip the backoff wait for a machine that is down (the refresh action).
  function retryNow() {
    if (!active) return
    if (proc.running && status !== "offline") return
    attempts = 0
    restart()
  }

  function reset() {
    sample = null
    info = ({})
    history = Model.emptyHistory()
  }

  property bool restartPending: false
  // Set while Vitals ends a process on purpose, so whatever the dying ssh (or
  // its ProxyCommand) prints is not shown as the reason for a failure.
  property bool stopping: false
  property real startedAt: 0

  function ingest(line) {
    var data = Model.parseLine(line)
    if (!data) return
    lastSeen = Date.now()
    if (data.type === "hello") {
      info = data
      reason = ""
      return
    }
    if (data.type === "error") {
      reason = data.message
      return
    }
    sample = data
    history = Model.pushSample(history, data, historyLength)
    status = "online"
    reason = ""
    attempts = 0
  }

  onActiveChanged: {
    if (active) { reset(); attempts = 0; start() }
    else stop()
  }
  onCommandChanged: if (active && proc.running) restart()
  onHistoryLengthChanged: history = Model.trimHistory(history, historyLength)
  Component.onCompleted: if (active) start()
  Component.onDestruction: {
    destroying = true
    retryTimer.stop()
    if (proc.running) proc.running = false
  }

  Process {
    id: proc
    stdout: SplitParser {
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
      if (root.restartPending) {
        root.restartPending = false
        root.start()
        return
      }
      if (!root.active) { root.status = "idle"; return }
      root.status = "offline"
      if (!root.reason) root.reason = root.isLocal ? "Sampler stopped" : "Connection lost"
      root.attempts += 1
      var wait = Model.backoffMs(root.attempts)
      root.retryAt = Date.now() + wait
      retryTimer.interval = wait
      retryTimer.restart()
    }
  }

  Timer {
    id: retryTimer
    repeat: false
    onTriggered: root.start()
  }

  // Samples stopped while the process is still up: a frozen link that ssh's
  // keepalive has not given up on yet. Stale after three quiet intervals;
  // after a longer silence (or a connect that never produced a line) the
  // process is ended so the normal reconnect path takes over.
  Timer {
    interval: 1000
    repeat: true
    running: root.active && proc.running
    onTriggered: {
      var now = Date.now()
      var staleAfter = Model.staleAfterMs(root.intervalSeconds)
      var since = Math.max(root.lastSeen, root.startedAt)
      if (root.status === "online" && now - root.lastSeen > staleAfter) root.status = "stale"
      if (now - since > staleAfter + 20000) {
        root.reason = root.lastSeen > root.startedAt ? "No data, reconnecting" : "No response"
        proc.running = false
      }
    }
  }
}
