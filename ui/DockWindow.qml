import QtQuick
import Quickshell
import Quickshell.Wayland

// Dock mode: a narrow layer-shell panel pinned to the left or right edge. It
// reserves its width as an exclusive zone, so Hyprland tiles windows beside
// it, and like the bar it shows on every workspace.
PanelWindow {
  id: window

  property var service: null
  readonly property string edge: service ? service.edge : "right"

  screen: service ? service.targetScreen : null
  color: "transparent"
  implicitWidth: service ? service.panelWidth : 200

  anchors {
    top: true
    bottom: true
    left: window.edge === "left"
    right: window.edge !== "left"
  }

  exclusionMode: ExclusionMode.Auto
  WlrLayershell.namespace: "vitals"
  WlrLayershell.layer: WlrLayer.Top
  // Typing into the machine editor needs the keyboard; the rest of the time
  // the sidebar never takes focus from the windows beside it.
  WlrLayershell.keyboardFocus: service && service.editor ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  // The popout beside it sizes itself to this.
  onHeightChanged: if (service) service.dockHeight = height
  Component.onCompleted: if (service) service.dockHeight = height

  VitalsView {
    anchors.fill: parent
    service: window.service
    edge: window.edge
  }
}
