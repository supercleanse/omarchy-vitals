import QtQuick
import qs.Commons
import qs.Commons as Commons

// A labeled single-line text input in the theme's control colors.
Column {
  id: root

  property string label: ""
  property string placeholder: ""
  property string hint: ""
  property alias text: input.text
  property alias input: input
  property color color: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property bool readOnly: false

  signal accepted()

  spacing: Style.space(4)

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.label
    color: Util.alpha(root.color, 0.7)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    renderType: Text.NativeRendering
  }

  Rectangle {
    width: parent.width
    height: Style.space(26)
    radius: Style.cornerRadius
    color: Util.alpha(root.color, root.readOnly ? 0.02 : 0.06)
    border.width: 1
    border.color: input.activeFocus ? root.accent : Util.alpha(root.color, 0.22)

    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: Style.space(7)
      anchors.rightMargin: Style.space(7)
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      readOnly: root.readOnly
      color: root.color
      selectionColor: Util.alpha(root.accent, 0.45)
      selectedTextColor: root.color
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      selectByMouse: true
      maximumLength: 255
      onAccepted: root.accepted()

      Text {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        visible: input.text === "" && !input.activeFocus
        textFormat: Text.PlainText
        text: root.placeholder
        color: Util.alpha(root.color, 0.38)
        font: input.font
        elide: Text.ElideRight
        renderType: Text.NativeRendering
      }
    }
  }

  Text {
    visible: root.hint !== ""
    width: parent.width
    textFormat: Text.PlainText
    text: root.hint
    wrapMode: Text.WordWrap
    color: Util.alpha(root.color, 0.5)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    renderType: Text.NativeRendering
  }
}
