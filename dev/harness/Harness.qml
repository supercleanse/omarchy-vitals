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
  // "main" renders the sidebar, settings and widget scenes; "detail" the
  // detail panels beside the dock.
  readonly property string sceneSet: Quickshell.env("VITALS_SET") || "main"
  readonly property bool detailSet: sceneSet === "detail" || sceneSet === "detail-mac"
  readonly property bool macSet: sceneSet === "detail-mac"

  FakeService { id: fakeDock }
  FakeService { id: fakeMany; set: "many" }
  FakeService { id: fakeWindow; panelWidth: 220 }
  FakeService { id: fakeWindowSettings; set: "mac"; panelWidth: 300; settingsId: "studio-mini" }
  FakeService { id: fakeLooks; set: "looks" }
  FakeService { id: fakeIcons; set: "looks"; labelMode: "icon"; temperatureUnit: "Fahrenheit" }
  FakeService { id: fakeEdit; editing: true }
  FakeService {
    id: fakeEditor
    editing: true
    editor: ({ id: "", alias: "studio-mini", host: "studio-mini", enabled: true })
  }
  FakeService { id: fakeSettingsLinux; settingsId: "local" }
  FakeService { id: fakeSettingsMac; set: "mac"; settingsId: "studio-mini" }
  FakeService { id: fakePreview; settingsId: "local" }
  FakeService { id: fdLinuxCpu; detailId: "local"; detailTab: "cpu"; popoutY: 44 }
  FakeService { id: fdLinuxMem; detailId: "local"; detailTab: "memory"; popoutY: 44 }
  FakeService { id: fdLinuxNet; detailId: "local"; detailTab: "network"; popoutY: 44 }
  FakeService { id: fdLinuxDisks; detailId: "local"; detailTab: "disks"; popoutY: 44 }
  FakeService { id: fdLinuxSensors; detailId: "local"; detailTab: "sensors"; popoutY: 44 }
  FakeService { id: fdLinuxBattery; detailId: "local"; detailTab: "battery"; popoutY: 44 }
  FakeService { id: fdLinuxGpu; detailId: "local"; detailTab: "gpu"; popoutY: 44 }
  FakeService { id: fdMacCpu; detailId: "studio-mini"; detailTab: "cpu"; popoutY: 330 }
  FakeService { id: fdMacMem; detailId: "studio-mini"; detailTab: "memory"; popoutY: 330 }
  FakeService { id: fdMacGpu; detailId: "studio-mini"; detailTab: "gpu"; popoutY: 330 }
  FakeService { id: fdMacNet; detailId: "studio-mini"; detailTab: "network"; popoutY: 330 }
  FakeService { id: fdMacDisks; detailId: "studio-mini"; detailTab: "disks"; popoutY: 330 }
  FakeService { id: fdWindow; detailId: "local"; detailTab: "cpu"; panelWidth: 400 }
  FakeService { id: fdPreview; detailId: "local"; detailTab: "cpu"; popoutY: 44 }
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

  component SettingsFrame: Rectangle {
    id: frame
    property var service: null
    width: 380
    implicitHeight: page.implicitHeight + Style.spacing.popupPadding * 2 + 2
    height: implicitHeight
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Commons.Color.popups.border

    UI.MachineSettings {
      id: page
      x: Style.spacing.popupPadding
      y: Style.spacing.popupPadding
      width: frame.width - Style.spacing.popupPadding * 2
      service: frame.service
      machineId: frame.service ? frame.service.settingsId : ""
    }
  }

  // The dock with a detail panel open beside it, placed the way SidePopout
  // places it: left of the sidebar, level with the clicked card, kept on
  // screen.
  component DetailScene: Rectangle {
    id: scene
    property var service: null
    property bool withBar: false
    readonly property real gap: Style.gapsOut
    readonly property real barTop: withBar ? harness.barSize : 0
    readonly property real available: height - barTop
    width: 1180
    height: 1000
    color: Commons.Color.background

    Rectangle {
      visible: scene.withBar
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
      id: sidebar
      y: scene.barTop
      anchors.right: parent.right
      width: 200
      height: scene.available
      service: scene.service
      edge: "right"
    }

    Rectangle {
      id: frame
      readonly property real wanted: panel.contentHeight + 2
      width: panel.implicitWidth + 2
      height: Math.max(160, Math.min(wanted, scene.available - scene.gap * 2))
      x: sidebar.x - scene.gap - width
      y: scene.barTop + Math.max(scene.gap, Math.min(scene.service ? scene.service.popoutY : 0, scene.available - height - scene.gap))
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.width: Math.max(1, Style.normalBorderWidth)
      border.color: Commons.Color.popups.border

      UI.DetailPanel {
        id: panel
        anchors.fill: parent
        anchors.margins: 1
        service: scene.service
      }
    }
  }

  FloatingWindow {
    id: stage
    implicitWidth: harness.detailSet ? 4820 : 2600
    implicitHeight: harness.detailSet ? 2120 : 2400
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
      visible: harness.fakeData && harness.detailSet

      DetailScene { id: dLinuxCpu; x: 20; y: 20; visible: !harness.macSet; service: fdLinuxCpu }
      DetailScene { id: dLinuxMem; x: 1220; y: 20; visible: !harness.macSet; service: fdLinuxMem }
      DetailScene { id: dLinuxNet; x: 2420; y: 20; visible: !harness.macSet; service: fdLinuxNet }
      DetailScene { id: dLinuxDisks; x: 3620; y: 20; visible: !harness.macSet; service: fdLinuxDisks }
      DetailScene { id: dLinuxSensors; x: 20; y: 1060; visible: !harness.macSet; service: fdLinuxSensors }
      DetailScene { id: dLinuxBattery; x: 1220; y: 1060; visible: !harness.macSet; service: fdLinuxBattery }
      DetailScene { id: dLinuxGpu; x: 2420; y: 1060; visible: !harness.macSet; service: fdLinuxGpu }
      DetailScene { id: dMacCpu; x: 20; y: 20; visible: harness.macSet; service: fdMacCpu }
      DetailScene { id: dMacMem; x: 1220; y: 20; visible: harness.macSet; service: fdMacMem }
      DetailScene { id: dMacGpu; x: 2420; y: 20; visible: harness.macSet; service: fdMacGpu }
      DetailScene { id: dMacNet; x: 3620; y: 20; visible: harness.macSet; service: fdMacNet }
      DetailScene { id: dMacDisks; x: 20; y: 1060; visible: harness.macSet; service: fdMacDisks }
      DetailScene { id: dPreview; x: 1220; y: 1060; height: 1040; withBar: true; visible: harness.macSet; service: fdPreview }

      Rectangle {
        id: dWindow
        visible: harness.macSet
        x: 2420; y: 1060
        width: 404; height: 1000
        color: "transparent"
        border.width: 2
        border.color: Commons.Color.accent

        UI.VitalsView {
          anchors.fill: parent
          anchors.margins: 2
          service: fdWindow
          showClose: false
          inlineSettings: true
        }
      }
    }

    Item {
      anchors.fill: parent
      visible: harness.fakeData && !harness.detailSet

      UI.VitalsView {
        id: dockScene
        x: 20; y: 20
        width: 200; height: 1000
        service: fakeDock
        edge: "right"
      }

      UI.VitalsView {
        id: manyScene
        x: 240; y: 20
        width: 200; height: 1000
        service: fakeMany
        edge: "right"
      }

      Rectangle {
        id: windowScene
        x: 460; y: 20
        width: 224; height: 760
        color: "transparent"
        border.width: 2
        border.color: Commons.Color.accent

        UI.VitalsView {
          anchors.fill: parent
          anchors.margins: 2
          service: fakeWindow
          showClose: false
          inlineSettings: true
        }
      }

      Rectangle {
        id: windowSettingsScene
        x: 700; y: 20
        width: 304; height: 1000
        color: "transparent"
        border.width: 2
        border.color: Commons.Color.accent

        UI.VitalsView {
          anchors.fill: parent
          anchors.margins: 2
          service: fakeWindowSettings
          showClose: false
          inlineSettings: true
        }
      }

      UI.VitalsView {
        id: editScene
        x: 1020; y: 20
        width: 200; height: 460
        service: fakeEdit
        edge: "right"
      }

      UI.VitalsView {
        id: editorScene
        x: 1240; y: 20
        width: 200; height: 480
        service: fakeEditor
        edge: "right"
      }

      Rectangle {
        id: barScene
        x: 1020; y: 520
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

      // Every look side by side: the same machine with all seven modules,
      // set to each look in turn, then icons for labels.
      Rectangle {
        id: looksScene
        x: 1460; y: 20
        width: lookRow.implicitWidth + 20
        height: lookRow.implicitHeight + 20
        color: Commons.Color.bar.background

        Row {
          id: lookRow
          x: 10; y: 10
          spacing: 16

          Repeater {
            model: fakeLooks.machines.length + 1

            delegate: Column {
              required property int index
              readonly property var svc: index < fakeLooks.machines.length ? fakeLooks : fakeIcons
              readonly property var m: svc.machines[Math.min(index, svc.machines.length - 1)]
              width: 180
              spacing: 6

              Text {
                text: index < fakeLooks.machines.length ? "look: " + m.alias : "icons, \u00b0F"
                color: Commons.Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              UI.MachineCard {
                width: 180
                machine: m
                link: svc.linkFor(m.id)
                service: svc
                foreground: Commons.Color.bar.text
                fontFamily: Style.font.family
                figureWidth: 44
              }
            }
          }
        }
      }

      SettingsFrame { id: settingsLinuxScene; x: 1460; y: 520; service: fakeSettingsLinux }
      SettingsFrame { id: settingsMacScene; x: 1860; y: 520; service: fakeSettingsMac }

      // README preview: the bar's right end above the docked sidebar, with
      // one machine's settings open beside it.
      Rectangle {
        id: previewScene
        x: 20; y: 1060
        width: 720; height: 1000
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
          id: previewSidebar
          anchors.top: previewBar.bottom
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          width: 200
          service: fakePreview
          edge: "right"
        }

        SettingsFrame {
          anchors.top: previewBar.bottom
          anchors.topMargin: Style.gapsOut
          anchors.right: previewSidebar.left
          anchors.rightMargin: Style.gapsOut
          height: Math.min(implicitHeight, parent.height - harness.barSize - Style.gapsOut * 2)
          clip: true
          service: fakePreview
        }
      }
    }

    property var scenes: harness.macSet ? [
      ["detail-macos-cpu", dMacCpu], ["detail-macos-memory", dMacMem], ["detail-macos-gpu", dMacGpu],
      ["detail-macos-network", dMacNet], ["detail-macos-disks", dMacDisks],
      ["detail-window", dWindow], ["preview", dPreview]
    ] : harness.detailSet ? [
      ["detail-linux-cpu", dLinuxCpu], ["detail-linux-memory", dLinuxMem], ["detail-linux-network", dLinuxNet],
      ["detail-linux-disks", dLinuxDisks], ["detail-linux-sensors", dLinuxSensors], ["detail-linux-battery", dLinuxBattery],
      ["detail-linux-gpu", dLinuxGpu]
    ] : [
      ["dock", dockScene], ["dock-8-machines", manyScene], ["window", windowScene],
      ["window-settings", windowSettingsScene], ["looks", looksScene],
      ["settings-linux", settingsLinuxScene], ["settings-macos", settingsMacScene],
      ["edit-list", editScene], ["editor", editorScene], ["bar-widget", barScene],
      ["preview-settings", previewScene]
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
