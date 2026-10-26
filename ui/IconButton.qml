import QtQuick
import qs.Commons
import qs.Commons as Commons

// A small square glyph button in the theme's control colors.
Item {
  id: root

  property string glyph: ""
  property color color: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property real glyphSize: Style.font.icon
  property bool selected: false
  property string label: ""

  signal clicked()

  implicitWidth: Style.space(22)
  implicitHeight: Style.space(22)
  opacity: enabled ? 1 : 0.35

  Rectangle {
    anchors.fill: parent
    radius: Math.min(Style.cornerRadius, height / 2)
    color: mouse.pressed ? Util.alpha(root.color, 0.22)
      : (mouse.containsMouse || root.selected ? Util.alpha(root.color, root.selected ? 0.16 : 0.10) : "transparent")
  }

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.glyph
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.glyphSize
    renderType: Text.NativeRendering
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
