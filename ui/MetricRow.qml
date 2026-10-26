import QtQuick
import qs.Commons
import qs.Commons as Commons

// One readout row in the OmaStats bar style: a stacked letter label, a bar
// history that fills the middle, and a right-aligned figure. `kind` is "bars"
// (stacked series against a 0–100 ceiling) or "mirror" (up/down rates).
Item {
  id: root

  property string label: "CPU"
  property string kind: "bars"
  property var series: []
  property var colors: []
  property var up: []
  property var down: []
  property color upColor: Commons.Color.accent
  property color downColor: Commons.Color.accent
  // Figure: a large first line, or two caption lines when `twoLine`.
  property string figure: ""
  property string figureSecond: ""
  property bool twoLine: false
  property color figureColor: foreground
  property color secondColor: foreground
  property real figureWidth: 40
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  implicitHeight: Style.space(25)

  StackLabel {
    id: stack
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: root.foreground
    fontFamily: root.fontFamily
    letterSize: Style.spaceReal(10)
    maxHeight: root.height - Style.space(2)
  }

  Item {
    id: graphBox
    anchors.left: stack.right
    anchors.leftMargin: Style.space(6)
    anchors.right: figureBox.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    height: root.height - Style.space(6)

    HistoryGraph {
      anchors.fill: parent
      visible: root.kind === "bars"
      ceiling: 100
      series: root.series
      colors: root.colors
      baselineColor: Util.alpha(root.foreground, 0.28)
    }

    MirrorGraph {
      anchors.fill: parent
      visible: root.kind === "mirror"
      up: root.up
      down: root.down
      upColor: root.upColor
      downColor: root.downColor
      midlineColor: Util.alpha(root.foreground, 0.32)
    }
  }

  Column {
    id: figureBox
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: root.figureWidth
    spacing: 0

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: root.figure
      color: root.figureColor
      font.family: root.fontFamily
      font.pixelSize: root.twoLine ? Style.font.caption : Style.font.body
      lineHeight: root.twoLine ? 0.95 : 1
      renderType: Text.NativeRendering
    }

    Text {
      visible: root.figureSecond !== ""
      width: parent.width
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: root.figureSecond
      color: root.secondColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      lineHeight: 0.95
      renderType: Text.NativeRendering
    }
  }
}
