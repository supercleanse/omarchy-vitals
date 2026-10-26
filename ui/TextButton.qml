import QtQuick
import qs.Commons
import qs.Commons as Commons

// A compact labeled button. `primary` fills with the accent.
Item {
  id: root

  property string text: ""
  property string glyph: ""
  property color color: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color background: Commons.Color.background
  property string fontFamily: Style.font.family
  property bool primary: false

  signal clicked()

  implicitWidth: row.implicitWidth + Style.space(16)
  implicitHeight: Style.space(24)
  opacity: enabled ? 1 : 0.4

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.primary
      ? (mouse.pressed ? Qt.darker(root.accent, 1.15) : root.accent)
      : (mouse.pressed ? Util.alpha(root.color, 0.22) : Util.alpha(root.color, mouse.containsMouse ? 0.12 : 0.06))
    border.width: root.primary ? 0 : 1
    border.color: Util.alpha(root.color, mouse.containsMouse ? 0.32 : 0.18)
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(5)

    Text {
      visible: root.glyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.glyph
      color: root.primary ? root.background : root.color
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.text
      color: root.primary ? root.background : root.color
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: root.primary
      renderType: Text.NativeRendering
    }
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
