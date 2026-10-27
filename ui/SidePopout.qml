import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Dock mode: the popout beside the sidebar, the way OmaStats opens its panel
// beside the bar. One slot holds either a machine's detail panel or its
// settings page. It reserves no space; with the normal exclusion mode the
// compositor places it inside the area the bar and the sidebar leave free,
// so it sits right next to the sidebar (left of it, or right of it when the
// dock is on the left), level with the card that opened it.
PanelWindow {
  id: window

  property var service: null
  readonly property string edge: service ? service.edge : "right"
  readonly property real gap: Style.gapsOut
  readonly property bool showingDetail: !!service && service.detailId !== ""
  // The height the sidebar has (the screen below the bar).
  readonly property real available: service && service.dockHeight > 0 ? service.dockHeight
    : (screen ? screen.height - Style.space(40) : 1000)
  readonly property real wanted: showingDetail
    ? detailPanel.contentHeight + 2
    : settingsPage.implicitHeight + Style.spacing.popupPadding * 2 + 2

  screen: service ? service.targetScreen : null
  color: "transparent"
  // As wide as OmaStats would make the panel, but never wider than the room
  // beside the sidebar; its tab strip abbreviates when squeezed, as OmaStats'
  // does on a narrow screen.
  readonly property real room: (screen ? screen.width : 1920) - (service ? service.panelWidth : 200) - gap * 3
  implicitWidth: showingDetail ? Math.min(detailPanel.implicitWidth + 2, room) : Style.space(380)
  implicitHeight: Math.max(Style.space(160), Math.min(wanted, available - gap * 2))

  anchors {
    top: true
    left: window.edge === "left"
    right: window.edge !== "left"
  }
  margins {
    top: Math.max(window.gap, Math.min(service ? service.popoutY : 0, window.available - window.implicitHeight - window.gap))
    left: window.edge === "left" ? window.gap : 0
    right: window.edge !== "left" ? window.gap : 0
  }

  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  WlrLayershell.namespace: "vitals-panel"
  WlrLayershell.layer: WlrLayer.Top
  // A brief exclusive grab when it opens, so Escape and the arrow keys work
  // at once (as OmaStats' panel does), then focus only on demand.
  property bool primed: false
  WlrLayershell.keyboardFocus: primed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
  Timer { interval: 250; running: true; onTriggered: window.primed = true }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Commons.Color.popups.border

    DetailPanel {
      id: detailPanel
      anchors.fill: parent
      anchors.margins: 1
      visible: window.showingDetail
      focus: window.showingDetail
      service: window.service
    }

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      visible: !window.showingDetail
      clip: true
      contentWidth: width
      contentHeight: settingsPage.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      MachineSettings {
        id: settingsPage
        width: flick.width
        focus: !window.showingDetail
        service: window.service
        machineId: window.service ? window.service.settingsId : ""
        onCloseRequested: if (window.service) window.service.closeSettings()
      }
    }
  }
}
