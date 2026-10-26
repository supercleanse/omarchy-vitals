import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "../../ui" as UI
import "../.." as Plugin

// Offscreen render harness. dev/render.sh runs this under Quickshell with
// QT_QPA_PLATFORM=offscreen and fake data from fixtures.js, then every scene
// is saved as a PNG. It never opens anything on a real display.
Scope {
  id: harness

  readonly property bool fakeData: Quickshell.env("VITALS_FAKE_DATA") === "1"
  readonly property string outDir: Quickshell.env("VITALS_OUT") || "."
  readonly property string tag: Quickshell.env("VITALS_THEME_TAG") || "theme"
  readonly property int barSize: Style.bar.sizeHorizontal

  FakeService { id: fakeDock }
  FakeService { id: fakeMany; many: true }
  FakeService { id: fakeWindow; panelWidth: 220 }
  FakeService { id: fakeEdit; editing: true }
  FakeService {
    id: fakeEditor
    editing: true
    editor: ({ id: "", alias: "studio-mini", host: "studio-mini", enabled: true })
  }
  FakeService { id: fakeBarClosed; open: false; sampling: false }
  FakeService { id: fakeBarCount }

  // The few bar members VitalsWidget and WidgetButton read.
  component FakeBar: QtObject {
    property var service: null
    property var shell: QtObject {
      property var target: null
      function serviceFor(id) { return target }
    }
    property color foreground: Commons.Color.bar.text
    property color barForeground: Commons.Color.bar.text
    property color background: Commons.Color.bar.background
    property color urgent: Commons.Color.urgent
    property string fontFamily: Style.font.family
    property bool vertical: false
    property bool transparent: false
    property bool foregroundAnimationEnabled: false
    property int barSize: harness.barSize
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    Component.onCompleted: shell.target = service
  }

  FakeBar { id: barClosed; service: fakeBarClosed }
  FakeBar { id: barOpen; service: fakeDock }
  FakeBar { id: barCount; service: fakeBarCount }

  FloatingWindow {
    id: stage
    implicitWidth: 1500
    implicitHeight: 1600
    color: Commons.Color.background
    visible: true

    Text {
      visible: !harness.fakeData
      anchors.centerIn: parent
      text: "Run through dev/render.sh --fake-data"
      color: Commons.Color.foreground
    }

    Item {
      anchors.fill: parent
      visible: harness.fakeData

      UI.VitalsView {
        id: dockScene
        x: 20; y: 20
        width: 200; height: 720
        service: fakeDock
        edge: "right"
      }

      UI.VitalsView {
        id: manyScene
        x: 240; y: 20
        width: 200; height: 720
        service: fakeMany
        edge: "right"
      }

      Rectangle {
        id: windowScene
        x: 460; y: 20
        width: 224; height: 564
        color: "transparent"
        border.width: 2
        border.color: Commons.Color.accent

        UI.VitalsView {
          anchors.fill: parent
          anchors.margins: 2
          service: fakeWindow
          showClose: false
        }
      }

      UI.VitalsView {
        id: editScene
        x: 700; y: 20
        width: 200; height: 460
        service: fakeEdit
        edge: "right"
      }

      UI.VitalsView {
        id: editorScene
        x: 920; y: 20
        width: 200; height: 460
        service: fakeEditor
        edge: "right"
      }

      Rectangle {
        id: barScene
        x: 1140; y: 20
        width: 420; height: harness.barSize
        color: Commons.Color.bar.background

        Row {
          anchors.right: parent.right
          anchors.rightMargin: 12
          height: parent.height
          spacing: 18

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "closed"
            color: Util.alpha(Commons.Color.bar.text, 0.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Plugin.VitalsWidget { bar: barClosed; height: parent.height; settings: ({}) }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "open"
            color: Util.alpha(Commons.Color.bar.text, 0.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Plugin.VitalsWidget { bar: barOpen; height: parent.height; settings: ({}) }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "count"
            color: Util.alpha(Commons.Color.bar.text, 0.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Plugin.VitalsWidget { bar: barCount; height: parent.height; settings: ({ barReadout: "count" }) }
        }
      }

      // README preview: the bar's right end above the docked sidebar, then
      // the machine list and the editor.
      Rectangle {
        id: previewScene
        x: 20; y: 860
        width: 700; height: 680
        color: Commons.Color.background

        Rectangle {
          id: previewBar
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: harness.barSize
          color: Commons.Color.bar.background

          Plugin.VitalsWidget {
            anchors.right: parent.right
            anchors.rightMargin: 64
            height: parent.height
            bar: barOpen
            settings: ({})
          }
        }

        UI.VitalsView {
          anchors.top: previewBar.bottom
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          width: 200
          service: fakeDock
          edge: "right"
        }

        UI.VitalsView {
          x: 40
          anchors.top: previewBar.bottom
          anchors.topMargin: 24
          width: 200; height: 520
          service: fakeEdit
          border.width: 1
          border.color: Util.alpha(Commons.Color.foreground, 0.15)
        }

        UI.VitalsView {
          x: 264
          anchors.top: previewBar.bottom
          anchors.topMargin: 24
          width: 200; height: 440
          service: fakeEditor
          border.width: 1
          border.color: Util.alpha(Commons.Color.foreground, 0.15)
        }
      }
    }

    property var scenes: [
      ["dock", dockScene], ["dock-8-machines", manyScene], ["window", windowScene],
      ["edit-list", editScene], ["editor", editorScene], ["bar-widget", barScene],
      ["preview", previewScene]
    ]
    property int pending: 0

    function saveAll() {
      if (!harness.fakeData) { console.log("refusing to render without --fake-data"); Qt.quit(); return }
      pending = scenes.length
      for (var i = 0; i < scenes.length; i++) {
        (function(name, item) {
          item.grabToImage(function(result) {
            var file = harness.outDir + "/" + name + "-" + harness.tag + ".png"
            result.saveToFile(file)
            console.log("saved " + file)
            stage.pending -= 1
            if (stage.pending === 0) Qt.quit()
          })
        })(scenes[i][0], scenes[i][1])
      }
    }

    Timer {
      interval: 2500
      running: true
      onTriggered: stage.saveAll()
    }
  }
}
