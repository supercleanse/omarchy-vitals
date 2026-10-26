import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "ui/Glyphs.js" as Glyphs

// Bar entry point: a pulse glyph that opens and closes the Vitals sidebar.
// Left click toggles it, middle click reconnects anything offline, right
// click opens it in edit mode. Optionally shows "online/total" beside the
// glyph. Every copy of the widget reports its settings to the one service.
BarWidget {
  id: root

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(Model.PLUGIN_ID) : null
  readonly property string instanceKey: Model.PLUGIN_ID + ":" + Math.random().toString(36).slice(2, 8)
  readonly property bool showCount: Model.resolveSettings(settings).barReadout === "count" && !vertical
  readonly property bool isOpen: !!service && service.open
  readonly property int total: service ? service.enabledMachines.length : 0
  // While hidden and still sampling, the icon is the only sign that a
  // machine dropped off, so it takes the theme's danger color then.
  readonly property bool flagOffline: !!service && !service.open && service.sampling && service.offlineCount > 0

  function pushSettings() {
    if (service) service.registerSettings(instanceKey, settings)
  }

  function tooltip() {
    if (!service) return "Vitals: service not loaded. Re-enable the plugin."
    if (!service.sampling) return "Vitals · " + total + (total === 1 ? " machine" : " machines") + "\nClick to show"
    var text = "Vitals · " + service.onlineCount + "/" + total + " online"
    if (service.offlineCount > 0) text += " · " + service.offlineCount + " offline"
    return text + "\nClick to " + (isOpen ? "hide" : "show") + " · middle-click to reconnect · right-click to edit"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onSettingsChanged: pushSettings()
  onServiceChanged: pushSettings()
  Component.onCompleted: pushSettings()
  Component.onDestruction: if (service) service.unregisterSettings(instanceKey)

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showCount && root.service && root.service.sampling
      ? Glyphs.pulse + " " + root.service.onlineCount + "/" + root.total
      : Glyphs.pulse
    fontSize: Style.bar.iconFont
    foreground: root.flagOffline ? (root.service ? root.service.danger : Commons.Color.urgent)
      : (root.isOpen ? Commons.Color.accent : (root.bar ? root.bar.barForeground : Commons.Color.foreground))
    tooltipText: root.tooltip()
    onPressed: function(mouseButton) {
      if (!root.service) return
      if (mouseButton === Qt.MiddleButton) root.service.refresh()
      else if (mouseButton === Qt.RightButton) {
        root.service.setEditing(true)
        root.service.show()
      } else root.service.toggle()
    }
  }
}
