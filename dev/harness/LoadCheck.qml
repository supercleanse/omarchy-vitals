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
    implicitWidth: 260
    implicitHeight: 900
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
      height: 860
      service: service
      edge: "right"
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
