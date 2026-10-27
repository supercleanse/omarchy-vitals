import QtQuick
import Quickshell

// Window mode: the same content in an ordinary toplevel window, which
// Hyprland tiles like any app. Its class is Quickshell's (org.quickshell) and
// its title is "Vitals", for window rules.
FloatingWindow {
  id: window

  property var service: null

  title: "Vitals"
  color: view.surface
  implicitWidth: service ? service.panelWidth : 200
  implicitHeight: 640

  // Closing the window from the compositor (killactive) hides Vitals.
  onClosed: if (service) service.hide()

  VitalsView {
    id: view
    anchors.fill: parent
    service: window.service
    showClose: false
    inlineSettings: true
  }
}
