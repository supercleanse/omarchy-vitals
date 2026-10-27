import QtQuick
import qs.Commons
import qs.Commons as Commons

// Tiny ring gauge for a fill level: CPU, memory, GPU, disk space, battery.
// Adapted from OmaStats by Carmine Paolino (MIT).
Item {
  id: root

  property real value: 0
  property color color: Commons.Color.accent
  property color trackColor: Util.alpha(Commons.Color.foreground, 0.22)
  property real size: Style.space(16)
  property real thickness: Style.spaceReal(2.4)
  readonly property real clamped: Math.max(0, Math.min(1, value))

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  onClampedChanged: canvas.requestPaint()
  onColorChanged: canvas.requestPaint()
  onTrackColorChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onVisibleChanged: if (visible) canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    renderStrategy: Canvas.Cooperative

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var r = Math.min(width, height) / 2 - root.thickness / 2
      if (r <= 0) return
      var cx = width / 2
      var cy = height / 2
      ctx.lineWidth = root.thickness
      ctx.lineCap = "butt"
      ctx.strokeStyle = root.trackColor
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.stroke()
      var v = root.clamped
      if (v <= 0.002) return
      ctx.strokeStyle = root.color
      ctx.lineCap = "round"
      ctx.beginPath()
      ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + v * Math.PI * 2)
      ctx.stroke()
    }
  }
}
