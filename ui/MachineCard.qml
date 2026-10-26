import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../Model.js" as Model

// One machine: a status dot and its alias, then CPU, MEM and NET rows while
// samples arrive. A machine that cannot be reached shows only that it is
// offline and reconnecting; it never shows numbers it does not have.
Item {
  id: root

  property var machine: ({})
  property var link: null
  property var service: null
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property real figureWidth: 40

  readonly property string status: link ? link.status : "idle"
  readonly property var sample: link ? link.sample : null
  readonly property var info: link ? (link.info || {}) : ({})
  readonly property var hist: link ? (link.history || Model.emptyHistory()) : Model.emptyHistory()
  readonly property bool showRows: (status === "online" || status === "stale") && sample !== null
  readonly property color s1: service ? service.series1 : Commons.Color.accent
  readonly property color s2: service ? service.series2 : Commons.Color.accent
  readonly property color good: service ? service.good : Commons.Color.accent
  readonly property color warn: service ? service.warn : Commons.Color.accent
  readonly property color danger: service ? service.danger : Commons.Color.urgent
  readonly property color dim: Util.alpha(foreground, 0.55)
  readonly property string alias: Model.displayAlias(machine, service ? service.localHostname : "")

  readonly property color dotColor: status === "online" ? good
    : (status === "offline" ? danger
    : (status === "idle" ? Util.alpha(foreground, 0.3) : warn))

  readonly property string retryText: {
    if (!link || status !== "offline") return ""
    var now = service ? service.clock : Date.now()
    var secs = Math.ceil((link.retryAt - now) / 1000)
    return secs > 0 ? "retry in " + secs + "s" : "retrying"
  }

  implicitHeight: header.height + body.implicitHeight + Style.space(6)

  Item {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(18)

    Rectangle {
      id: dot
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(7)
      height: width
      radius: width / 2
      color: root.dotColor
    }

    Text {
      anchors.left: dot.right
      anchors.leftMargin: Style.space(6)
      anchors.right: meta.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.alias
      elide: Text.ElideRight
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      renderType: Text.NativeRendering
    }

    Row {
      id: meta
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Text {
        visible: root.status === "stale"
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "stale"
        color: root.warn
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Text {
        visible: text !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.info.cores > 0 && root.showRows ? root.info.cores + "c" : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Text {
        visible: text !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.osGlyph(root.info.os)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }
    }
  }

  Column {
    id: body
    anchors.top: header.bottom
    anchors.topMargin: Style.space(3)
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.space(2)

    Column {
      width: parent.width
      visible: root.showRows
      spacing: Style.space(2)
      opacity: root.status === "stale" ? 0.45 : 1

      MetricRow {
        width: parent.width
        label: "CPU"
        kind: "bars"
        series: [root.hist.cpuUser || [], root.hist.cpuSys || []]
        colors: [root.s1, root.s2]
        figure: root.sample ? Model.percentText(root.sample.cpu) : ""
        figureWidth: root.figureWidth
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      MetricRow {
        width: parent.width
        label: "MEM"
        kind: "bars"
        series: [root.hist.mem || []]
        colors: [root.s1]
        figure: root.sample ? Model.percentText(root.sample.memPercent) : ""
        figureSecond: root.sample && root.sample.memTotal > 0 ? Model.compactPair(root.sample.memUsed, root.sample.memTotal) : ""
        secondColor: root.dim
        figureWidth: root.figureWidth
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      MetricRow {
        width: parent.width
        label: "NET"
        kind: "mirror"
        up: root.hist.tx || []
        down: root.hist.rx || []
        upColor: root.s2
        downColor: root.s1
        twoLine: true
        figure: root.sample ? "↑ " + Model.compactRate(root.sample.tx) : ""
        figureSecond: root.sample ? "↓ " + Model.compactRate(root.sample.rx) : ""
        figureWidth: root.figureWidth
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }

    Text {
      visible: !root.showRows
      width: parent.width
      textFormat: Text.PlainText
      text: root.status === "offline" ? "offline · reconnecting"
        : (root.status === "idle" ? (root.machine.enabled === false ? "off" : "paused") : "connecting…")
      color: root.status === "offline" ? root.danger : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }

    Text {
      visible: !root.showRows && text !== ""
      width: parent.width
      textFormat: Text.PlainText
      text: {
        if (!root.link) return ""
        var parts = []
        // Reasons only explain an outage; while connecting, warnings from ssh
        // or a ProxyCommand are not worth showing.
        if (root.status !== "offline") return ""
        if (root.link.reason) parts.push(root.link.reason)
        if (root.retryText) parts.push(root.retryText)
        return parts.join(" · ")
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      renderType: Text.NativeRendering
    }
  }
}
