import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "../../ui" as UI
import "../.." as Plugin

// Integration check for dev/load-check.sh: loads the real VitalsService and
// VitalsWidget (no fixtures) under a scratch HOME, lets the real samplers
// run, then prints the service summary and saves one PNG of the live view.
// Output goes to the scratch directory the script names, never the repo.
Scope {
  id: check

  readonly property string outDir: Quickshell.env("VITALS_OUT") || "."
  readonly property int waitMs: Number(Quickshell.env("VITALS_WAIT_MS") || 12000)
  readonly property string mode: Quickshell.env("VITALS_MODE") || "window"

  Plugin.VitalsService { id: service }

  QtObject {
    id: fakeBar
    property var shell: QtObject { function serviceFor(id) { return service } }
    property color foreground: Commons.Color.bar.text
    property color barForeground: Commons.Color.bar.text
    property color urgent: Commons.Color.urgent
    property string fontFamily: Style.font.family
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    property int barSize: Style.bar.sizeHorizontal
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
  }

  FloatingWindow {
    id: stage
    implicitWidth: 780
    implicitHeight: 1420
    color: Commons.Color.background
    visible: true

    Plugin.VitalsWidget {
      id: widget
      bar: fakeBar
      height: Style.bar.sizeHorizontal
      settings: ({ mode: check.mode, refreshSeconds: "2", historySeconds: 60 })
    }

    UI.VitalsView {
      id: view
      y: Style.bar.sizeHorizontal
      width: 200
      height: 1400
      service: service
      edge: "right"
    }

    // VITALS_MODULES: switch every remote to these modules through the
    // service's own update path, which also restarts their samplers.
    Timer {
      interval: 4000
      running: Quickshell.env("VITALS_MODULES") !== ""
      onTriggered: {
        var mods = Quickshell.env("VITALS_MODULES").split(",")
        for (var i = 0; i < service.machines.length; i++) {
          var m = service.machines[i]
          service.updateMachine(m.id, { modules: mods })
        }
        console.log("MODULES set to " + mods.join(","))
      }
    }

    // VITALS_DETAIL="machine:tab,machine:tab,...": open each detail panel in
    // turn through the service, as a readout click would, and report how
    // long the first sample took and what it carried.
    property var detailSteps: (Quickshell.env("VITALS_DETAIL") || "").split(",").filter(function(x) { return x !== "" })
    property int detailStep: -1
    property real openedAt: 0
    property bool reported: false

    function describe(snap) {
      var out = []
      if (snap.cpu && snap.cpu.cores) out.push("cores=" + snap.cpu.cores.length)
      if (snap.procs) out.push("procs=" + (snap.procs.total || 0) + (snap.procs.cpu ? " top=" + snap.procs.cpu.slice(0, 2).map(function(p) { return p.name }).join("/") : "") + (snap.procs.io ? " io=" + snap.procs.io.length : ""))
      if (snap.mem && snap.mem.total) out.push("mem=" + Math.round(snap.mem.used / snap.mem.total * 100) + "%")
      if (snap.net && snap.net.ifaces) out.push("ifaces=" + snap.net.ifaces.length + " netprocs=" + (snap.net.procs || []).length)
      if (snap.disks) out.push("volumes=" + (snap.disks.volumes || []).length + " perDisk=" + Object.keys(snap.disks.perDisk || {}).length)
      if (snap.sensors) out.push("temps=" + snap.sensors.temps.length + " fans=" + snap.sensors.fans.length)
      if (snap.battery) out.push("battery=" + snap.battery.percent + "% cycles=" + snap.battery.cycles + " health=" + snap.battery.health)
      if (snap.gpus) out.push("gpus=" + snap.gpus.map(function(g) { return g.name + ":" + g.util }).join("/"))
      return out.join(" ")
    }

    Timer {
      interval: Number(Quickshell.env("VITALS_DETAIL_STEP_MS") || 6000)
      repeat: true
      running: stage.detailSteps.length > 0
      onTriggered: {
        if (stage.detailStep >= 0 && !stage.reported) console.log("DETAIL " + stage.detailSteps[stage.detailStep] + " no data after " + interval + " ms")
        stage.detailStep += 1
        if (stage.detailStep >= stage.detailSteps.length) { service.closeDetail(); running = false; console.log("DETAIL closed, source active=" + service.detail.active); return }
        var parts = stage.detailSteps[stage.detailStep].split(":")
        stage.reported = false
        stage.openedAt = Date.now()
        service.openDetail(parts[0], parts[1], 40)
      }
    }

    Connections {
      target: service.detail
      function onSnapshotChanged() {
        if (stage.reported || stage.detailStep < 0 || !service.detail.ready) return
        stage.reported = true
        console.log("DETAIL " + stage.detailSteps[stage.detailStep] + " first sample after " + (Date.now() - stage.openedAt) + " ms: " + stage.describe(service.detail.snapshot))
        var name = stage.detailSteps[stage.detailStep].replace(/[^A-Za-z0-9]+/g, "-")
        livePanelShot.target = name
        livePanelShot.restart()
      }
    }

    // A moment after each panel fills, save it (scratch only: real data).
    Timer {
      id: livePanelShot
      property string target: ""
      interval: 2500
      onTriggered: livePanel.grabToImage(function(r) { r.saveToFile(check.outDir + "/live-detail-" + target + ".png") })
    }

    UI.DetailPanel {
      id: livePanel
      x: 0
      y: 0
      width: 760
      height: 1400
      service: service
    }

    Timer {
      interval: check.waitMs
      running: true
      onTriggered: {
        console.log("SUMMARY " + JSON.stringify(service.summary()))
        console.log("WIDGET tooltip=" + JSON.stringify(widget.tooltip()))
        view.grabToImage(function(result) {
          result.saveToFile(check.outDir + "/live-view.png")
          console.log("saved " + check.outDir + "/live-view.png")
          Qt.quit()
        })
      }
    }
  }
}
