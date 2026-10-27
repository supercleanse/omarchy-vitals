import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Dock mode: one machine's settings in a popout beside the sidebar, the way
// OmaStats opens its panel beside the bar. It reserves no space; with the
// normal exclusion mode the compositor places it inside the area the bar and
// the sidebar leave free, so it sits right next to the sidebar.
PanelWindow {
  id: window

  property var service: null
  readonly property string edge: service ? service.edge : "right"
  readonly property real gap: Style.gapsOut

  screen: service ? service.targetScreen : null
  color: "transparent"
  implicitWidth: Style.space(380)
  implicitHeight: Math.min(page.implicitHeight + Style.spacing.popupPadding * 2 + 2,
    (screen ? screen.height : 1000) - Style.space(96))

  anchors {
    top: true
    left: window.edge === "left"
    right: window.edge !== "left"
  }
  margins {
    top: window.gap
    left: window.edge === "left" ? window.gap : 0
    right: window.edge !== "left" ? window.gap : 0
  }

  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  WlrLayershell.namespace: "vitals-settings"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Commons.Color.popups.border

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      clip: true
      contentWidth: width
      contentHeight: page.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      MachineSettings {
        id: page
        width: flick.width
        focus: true
        service: window.service
        machineId: window.service ? window.service.settingsId : ""
        onCloseRequested: if (window.service) window.service.closeSettings()
      }
    }
  }
}
