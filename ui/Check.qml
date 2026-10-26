import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Glyphs.js" as Glyphs

// A small on/off box: filled with the accent and a check mark when on.
Item {
  id: root

  property bool checked: false
  property color color: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color background: Commons.Color.background
  property string fontFamily: Style.font.family

  signal toggled(bool value)

  implicitWidth: Style.space(16)
  implicitHeight: Style.space(16)

  Rectangle {
    anchors.fill: parent
    radius: Math.min(Style.cornerRadius, 3)
    color: root.checked ? root.accent : (mouse.containsMouse ? Util.alpha(root.color, 0.10) : "transparent")
    border.width: root.checked ? 0 : 1
    border.color: Util.alpha(root.color, 0.45)
  }

  Text {
    anchors.centerIn: parent
    visible: root.checked
    textFormat: Text.PlainText
    text: Glyphs.check
    color: root.background
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    renderType: Text.NativeRendering
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: -Style.space(3)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled(!root.checked)
  }
}
