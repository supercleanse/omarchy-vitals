import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../Model.js" as Model
import "Glyphs.js" as Glyphs

// A machine in edit mode: on/off, its name and destination, and buttons to
// move it, edit it, or remove it. The local machine can be renamed and
// switched off but not removed.
Item {
  id: root

  property var machine: ({})
  property var service: null
  property int position: 0
  property int count: 1
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  readonly property bool isLocal: machine.id === "local"
  readonly property string alias: Model.displayAlias(machine, service ? service.localHostname : "")

  implicitHeight: Style.space(42)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(root.foreground, hover.hovered ? 0.07 : 0.035)
    HoverHandler { id: hover }
  }

  Check {
    id: check
    anchors.left: parent.left
    anchors.leftMargin: Style.space(5)
    anchors.top: parent.top
    anchors.topMargin: Style.space(6)
    checked: root.machine.enabled !== false
    color: root.foreground
    accent: root.accent
    background: root.background
    fontFamily: root.fontFamily
    onToggled: function(value) { if (root.service) root.service.setMachineEnabled(root.machine.id, value) }
  }

  Column {
    anchors.left: check.right
    anchors.leftMargin: Style.space(6)
    anchors.right: buttons.left
    anchors.rightMargin: Style.space(2)
    anchors.top: check.top
    anchors.topMargin: -Style.space(1)
    spacing: Style.space(2)
    opacity: root.machine.enabled === false ? 0.5 : 1

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.alias
      elide: Text.ElideRight
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      renderType: Text.NativeRendering
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.isLocal ? "local" : root.machine.host
      elide: Text.ElideRight
      color: Util.alpha(root.foreground, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }
  }

  // Edit and remove on top, move up and down below.
  Grid {
    id: buttons
    anchors.right: parent.right
    anchors.rightMargin: Style.space(1)
    anchors.verticalCenter: parent.verticalCenter
    columns: 2
    spacing: 0

    IconButton {
      width: Style.space(17); height: Style.space(18)
      glyph: Glyphs.pencil
      glyphSize: Style.font.caption
      color: root.foreground
      fontFamily: root.fontFamily
      onClicked: if (root.service) root.service.openSettings(root.machine.id)
    }

    IconButton {
      width: Style.space(17); height: Style.space(18)
      glyph: Glyphs.trash
      glyphSize: Style.font.caption
      color: root.service ? root.service.danger : root.foreground
      fontFamily: root.fontFamily
      enabled: !root.isLocal
      opacity: root.isLocal ? 0 : 1
      onClicked: if (root.service) root.service.removeMachine(root.machine.id)
    }

    IconButton {
      width: Style.space(17); height: Style.space(18)
      glyph: Glyphs.up
      glyphSize: Style.font.caption
      color: root.foreground
      fontFamily: root.fontFamily
      enabled: root.position > 0
      onClicked: if (root.service) root.service.moveMachine(root.machine.id, -1)
    }

    IconButton {
      width: Style.space(17); height: Style.space(18)
      glyph: Glyphs.down
      glyphSize: Style.font.caption
      color: root.foreground
      fontFamily: root.fontFamily
      enabled: root.position < root.count - 1
      onClicked: if (root.service) root.service.moveMachine(root.machine.id, 1)
    }
  }
}
