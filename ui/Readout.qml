import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "../Model.js" as Model

// One readout on a machine card, in the OmaStats bar style: a stacked letter
// label (or an icon), then a graph, a ring and/or a figure as the look asks.
// `entry` comes from Model.readouts(): { module, style, label, gpuId, disk, show }.
// Nothing is drawn for a value the machine did not report.
Item {
  id: root

  property var entry: ({})
  property var machine: null
  property var link: null
  property var service: null
  property string labelMode: "text"
  property string temperatureUnit: "Celsius"
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property real figureWidth: 40
  // This readout's tab is the open detail panel for its machine.
  property bool selected: false

  // Clicking a readout opens (or closes) the machine's detail panel on this
  // module's tab.
  signal activated()

  readonly property string module: entry.module || "cpu"
  readonly property var def: Model.moduleDef(module)
  readonly property string style: entry.style || "both"
  readonly property var sample: link ? link.sample : null
  readonly property var hist: link && link.history ? link.history : Model.emptyHistory()
  readonly property var info: link && link.info ? link.info : ({})
  readonly property color s1: service ? service.series1 : Commons.Color.accent
  readonly property color s2: service ? service.series2 : Commons.Color.accent
  readonly property color dim: Util.alpha(foreground, 0.55)

  // --- what to draw
  readonly property bool isDisk: module === "disks"
  readonly property bool diskSpeed: isDisk && entry.show !== "used"
  readonly property bool diskUsed: isDisk && entry.show !== "speed"
  readonly property var gpu: module === "gpu" || module === "gpuMemory" ? Model.gpuSample(sample, entry.gpuId) : null
  readonly property bool gpuHasUtil: !!gpu && gpu.util !== null
  readonly property var space: isDisk ? Model.diskSpace(sample, entry.disk) : null
  readonly property var rates: isDisk ? Model.diskRates(sample, entry.disk) : null
  readonly property var battery: sample ? sample.battery : null

  readonly property bool wantsPicture: style === "graph" || style === "both" || style === "ring" || style === "ring-text"
  readonly property bool showGraph: {
    if (isDisk) return style !== "text" && diskSpeed && rates !== null
    if (!def.graph || !(style === "graph" || style === "both")) return false
    if (module === "gpu") return gpuHasUtil
    if (module === "gpuMemory") return ringValue !== null
    return true
  }
  readonly property bool showRing: {
    if (isDisk) return style !== "text" && diskUsed && space !== null
    return def.ring && (style === "ring" || style === "ring-text") && ringValue !== null
  }
  readonly property bool showFigure: {
    if (isDisk) return style !== "graph" || (!showGraph && !showRing)
    return style === "text" || style === "both" || style === "ring-text" || (!showGraph && !showRing)
  }
  readonly property bool twoLine: module === "network" || (isDisk && diskSpeed)

  // 0..1 for the ring, or null when there is nothing to fill.
  readonly property var ringValue: {
    if (!sample) return null
    switch (module) {
      case "cpu": return sample.cpu / 100
      case "memory": return sample.memTotal > 0 ? sample.memPercent / 100 : null
      case "gpu": return gpuHasUtil ? gpu.util / 100 : null
      case "gpuMemory": { var p = Model.gpuMemoryPercent(gpu); return p === null ? null : p / 100 }
      case "battery": return battery && battery.percent !== null ? battery.percent / 100 : null
      case "disks": return space ? space[0] / space[1] : null
    }
    return null
  }

  readonly property color ringColor: {
    if (!service) return s1
    if (module === "battery" && battery) {
      if (battery.status === "Charging" || battery.status === "Full") return service.good
      if (ringValue !== null && ringValue <= 0.15) return service.danger
    }
    if (module === "disks" && ringValue !== null) {
      if (ringValue >= 0.92) return service.danger
      if (ringValue >= 0.8) return service.warn
    }
    return s1
  }

  readonly property var series: {
    switch (module) {
      case "cpu": return [hist.cpuUser || [], hist.cpuSys || []]
      case "memory": return [hist.mem || []]
      case "gpu": return [(hist.gpu || {})[entry.gpuId || (gpu ? gpu.id : "")] || []]
      case "gpuMemory": return [(hist.gpuMem || {})[entry.gpuId || (gpu ? gpu.id : "")] || []]
    }
    return []
  }

  readonly property string figure: {
    if (!sample) return ""
    switch (module) {
      case "cpu": return Model.percentText(sample.cpu)
      case "memory": return Model.percentText(sample.memPercent)
      case "gpu": return gpu ? (gpuHasUtil ? Model.percentText(gpu.util) : Model.compactFreq(gpu.mhz)) : ""
      case "gpuMemory": { var p = Model.gpuMemoryPercent(gpu); return p === null ? "" : Model.percentText(p) }
      case "battery": return battery && battery.percent !== null ? Model.percentText(battery.percent) : ""
      case "network": return "↑ " + Model.compactRate(sample.tx)
      case "disks":
        if (diskSpeed) return rates ? "R " + Model.compactRate(rates[0]) : ""
        return space ? Model.percentText(space[0] / space[1] * 100) : ""
    }
    return ""
  }

  readonly property string figureSecond: {
    if (!sample) return ""
    if (module === "network") return "↓ " + Model.compactRate(sample.rx)
    if (isDisk && diskSpeed) return rates ? "W " + Model.compactRate(rates[1]) : ""
    if (module === "memory" && style === "both" && sample.memTotal > 0) return Model.compactPair(sample.memUsed, sample.memTotal)
    return ""
  }

  // Quiet context in the middle when no graph takes the space.
  readonly property string details: {
    if (!sample) return ""
    switch (module) {
      case "cpu": return "load " + Model.loadText(sample.load)
      case "memory": return sample.memTotal > 0 ? Model.compactPair(sample.memUsed, sample.memTotal) : ""
      case "gpu": {
        var parts = []
        if (gpu && gpu.temp !== null) parts.push(Model.tempText(gpu.temp, temperatureUnit))
        if (gpu && !gpuHasUtil) parts.push("clock")
        return parts.join(" · ")
      }
      case "gpuMemory": return gpu && gpu.memTotal > 0 ? Model.compactPair(gpu.memUsed, gpu.memTotal) : ""
      case "disks": return space ? Model.compactPair(space[0], space[1]) : ""
      case "battery": {
        if (!battery) return ""
        if (battery.status === "Charging") return battery.toFull !== null ? "charging · " + Model.clockText(battery.toFull) : "charging"
        if (battery.status === "Discharging") return battery.toEmpty !== null ? Model.clockText(battery.toEmpty) + " left" : "on battery"
        if (battery.status === "Full") return "full"
        return "plugged in"
      }
    }
    return ""
  }

  readonly property var sensorReadings: {
    if (module !== "sensors" || !sample) return []
    var ids = Model.machineSensors(machine, info)
    var out = []
    for (var i = 0; i < ids.length; i++) {
      var r = Model.sensorReading(sample, info, ids[i], temperatureUnit)
      if (r) out.push(r)
    }
    return out
  }

  readonly property string glyph: module === "battery" && battery && battery.percent !== null
    ? Model.batteryIcon(battery.percent, battery.status === "Charging")
    : def.icon

  TextMetrics {
    id: percentReserve
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    text: "100%"
  }

  implicitHeight: module === "sensors" ? Math.max(Style.space(25), sensorFlow.implicitHeight) : Style.space(25)
  visible: sample !== null && (module !== "sensors" || sensorReadings.length > 0)

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -Style.space(4)
    anchors.rightMargin: -Style.space(4)
    radius: Style.cornerRadius
    color: Util.alpha(root.foreground, root.selected ? 0.10 : (clickArea.containsMouse ? 0.06 : 0))
  }

  RowLayout {
    anchors.fill: parent
    spacing: Style.space(6)
    visible: root.module !== "sensors"

    Item {
      Layout.preferredWidth: labelLoader.item ? labelLoader.item.implicitWidth : 0
      Layout.fillHeight: true

      Loader {
        id: labelLoader
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: root.labelMode === "icon" ? iconLabel : stackLabel
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      HistoryGraph {
        anchors.fill: parent
        anchors.topMargin: Style.space(3)
        anchors.bottomMargin: Style.space(3)
        visible: root.showGraph && !root.twoLine
        ceiling: 100
        series: root.series
        colors: [root.s1, root.s2]
        baselineColor: Util.alpha(root.foreground, 0.28)
      }

      MirrorGraph {
        anchors.fill: parent
        anchors.topMargin: Style.space(3)
        anchors.bottomMargin: Style.space(3)
        visible: root.showGraph && root.twoLine
        up: root.module === "network" ? (root.hist.tx || []) : ((root.hist.diskRead || {})[root.entry.disk || "all"] || [])
        down: root.module === "network" ? (root.hist.rx || []) : ((root.hist.diskWrite || {})[root.entry.disk || "all"] || [])
        upColor: root.s2
        downColor: root.s1
        floor: root.module === "network" ? 10240 : 262144
        midlineColor: Util.alpha(root.foreground, 0.32)
      }

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.showGraph && text !== ""
        textFormat: Text.PlainText
        text: root.details
        elide: Text.ElideRight
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }

    MiniRing {
      visible: root.showRing
      Layout.alignment: Qt.AlignVCenter
      size: Style.space(17)
      value: root.ringValue === null ? 0 : root.ringValue
      color: root.ringColor
      trackColor: Util.alpha(root.foreground, 0.22)
    }

    Column {
      visible: root.showFigure
      // Rows with a graph share one figure width so their graphs line up;
      // a ring row only needs room for a percentage, which leaves more for
      // the details beside it.
      readonly property real columnWidth: root.showGraph || root.twoLine || root.figureSecond !== "" ? root.figureWidth : Math.ceil(percentReserve.advanceWidth)
      Layout.preferredWidth: columnWidth
      Layout.minimumWidth: columnWidth
      Layout.maximumWidth: columnWidth
      Layout.alignment: Qt.AlignVCenter
      spacing: 0

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: root.figure
        color: root.foreground
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
        color: root.twoLine ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        lineHeight: 0.95
        renderType: Text.NativeRendering
      }
    }
  }

  // Sensors: a label and a figure per picked sensor, wrapping when they
  // outgrow the row, as OmaStats lays them out in the bar.
  Flow {
    id: sensorFlow
    visible: root.module === "sensors"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(8)

    Repeater {
      model: root.module === "sensors" ? root.sensorReadings : []

      delegate: Row {
        required property var modelData
        spacing: Style.space(5)
        height: Style.space(22)

        StackLabel {
          visible: root.labelMode !== "icon"
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.short
          color: root.foreground
          fontFamily: root.fontFamily
          letterSize: Style.spaceReal(10)
          maxHeight: Style.space(23)
        }

        Text {
          visible: root.labelMode === "icon"
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: modelData.kind === "fan" ? String.fromCodePoint(0xF0210) : root.def.icon
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          renderType: Text.NativeRendering
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: modelData.text + (modelData.unit ? " " + modelData.unit : "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
        }
      }
    }
  }

  Component {
    id: stackLabel

    StackLabel {
      text: root.entry.label || root.def.short
      color: root.foreground
      fontFamily: root.fontFamily
      letterSize: Style.spaceReal(10)
      maxHeight: root.height - Style.space(2)
    }
  }

  Component {
    id: iconLabel

    Text {
      textFormat: Text.PlainText
      text: root.glyph
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
      renderType: Text.NativeRendering
    }
  }

  MouseArea {
    id: clickArea
    anchors.fill: parent
    anchors.leftMargin: -Style.space(4)
    anchors.rightMargin: -Style.space(4)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
