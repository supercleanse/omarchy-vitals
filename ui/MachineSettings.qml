import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Model.js" as Model
import "Glyphs.js" as Glyphs

// One machine's settings, modeled on OmaStats' Settings page: the machine's
// name and destination, which readouts its card shows and how, and the looks
// shared by every machine. Every change is saved straight away, the
// readouts to ~/.config/vitals/machines.json and the shared looks to the
// widget's entry in shell.json.
// Layout, controls and wording follow OmaStats by Carmine Paolino (MIT).
Column {
  id: root

  property var service: null
  property string machineId: ""
  property color foreground: Commons.Color.popups.text
  property string fontFamily: Style.font.family

  signal closeRequested()

  readonly property var machine: {
    var list = service ? service.machines : []
    for (var i = 0; i < list.length; i++) if (list[i].id === machineId) return list[i]
    return null
  }
  readonly property var link: service && machine ? service.linkFor(machineId) : null
  readonly property var info: link && link.info ? link.info : ({})
  readonly property var sample: link ? link.sample : null
  readonly property bool known: !!info.caps
  readonly property bool isLocal: machineId === "local"
  readonly property string defaultStyle: service ? service.defaultStyle : "both"

  readonly property var available: Model.MODULE_IDS.filter(function(id) { return Model.moduleAvailable(id, root.info) })
  readonly property var unavailable: Model.MODULE_IDS.filter(function(id) {
    if (id === "sensors" && root.info.os === "macos") return false
    return !Model.moduleAvailable(id, root.info)
  })
  // The machine's own list, keeping modules it can't show right now so a
  // GPU that comes back later reappears where it was.
  readonly property var allModules: Model.machineModules(machine, service ? service.defaultModules : null)
  readonly property var shownModules: allModules.filter(function(id) { return root.available.indexOf(id) !== -1 })
  // Enabled readouts first, in card order, then the rest in canonical order.
  readonly property var orderedModules: {
    var out = shownModules.slice()
    for (var i = 0; i < available.length; i++) if (out.indexOf(available[i]) === -1) out.push(available[i])
    return out
  }
  readonly property var diskOptions: {
    var out = [{ value: "all", label: "All disks" }]
    var list = Model.asArray(info.disks) || []
    for (var i = 0; i < list.length; i++) out.push({ value: list[i], label: list[i] })
    return out
  }
  readonly property var diskList: Model.machineDisks(machine)
  readonly property var gpuOptions: Model.asArray(info.gpus) || []
  readonly property var gpuIds: Model.machineGpuIds(machine, info)
  readonly property var sensorOptions: Model.asArray(info.sensors) || []
  readonly property var sensorIds: Model.machineSensors(machine, info)
  readonly property bool anyVram: {
    var list = sample ? (Model.asArray(sample.gpus) || []) : []
    for (var i = 0; i < list.length; i++) if (Model.gpuMemoryPercent(list[i]) !== null) return true
    return false
  }

  function update(patch) { if (service) service.updateMachine(machineId, patch) }

  function setModuleEnabled(id, enabled) {
    var list = allModules.slice()
    var at = list.indexOf(id)
    if (enabled && at === -1) list.push(id)
    if (!enabled && at !== -1) list.splice(at, 1)
    update({ modules: list })
  }

  // Move within the shown readouts, ignoring hidden ones between them.
  function moveModule(id, delta) {
    var shown = Model.moveInList(shownModules, id, delta)
    var hidden = allModules.filter(function(m) { return shown.indexOf(m) === -1 })
    update({ modules: shown.concat(hidden) })
  }

  function setStyle(id, value) {
    var styles = {}
    var own = machine && machine.styles ? machine.styles : {}
    for (var k in own) styles[k] = own[k]
    styles[id] = value
    update({ styles: styles })
  }

  function diskIndex(disk) {
    for (var i = 0; i < diskList.length; i++) if (diskList[i].disk === disk) return i
    return -1
  }

  function setDisk(disk, enabled, show) {
    var list = diskList.map(function(d) { return { disk: d.disk, show: d.show } })
    var at = diskIndex(disk)
    if (enabled && at === -1) list.push({ disk: disk, show: show || "speed" })
    else if (enabled && show) list[at].show = show
    if (!enabled && at !== -1) list.splice(at, 1)
    var order = diskOptions.map(function(o) { return o.value })
    list.sort(function(a, b) { return order.indexOf(a.disk) - order.indexOf(b.disk) })
    update({ disks: list })
  }

  function setGpu(id, enabled) {
    var list = gpuIds.slice()
    var at = list.indexOf(id)
    if (enabled && at === -1) list.push(id)
    if (!enabled && at !== -1) list.splice(at, 1)
    update({ gpus: list.length === gpuOptions.length ? "all" : list })
  }

  function setSensor(id, enabled) {
    var list = sensorIds.slice()
    var at = list.indexOf(id)
    if (enabled && at === -1) list.push(id)
    if (!enabled && at !== -1) list.splice(at, 1)
    update({ sensors: list })
  }

  function saveIdentity() {
    if (!service || !machine) return
    identityError.text = service.renameMachine(machineId, nameField.text, isLocal ? "" : hostField.text) || ""
  }

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(10)

  Keys.onEscapePressed: root.closeRequested()

  // ------------------------------------------------------------------ title
  Item {
    width: parent.width
    height: Style.space(28)

    Text {
      anchors.left: parent.left
      anchors.right: closeButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.machine ? Model.displayAlias(root.machine, root.service ? root.service.localHostname : "") : ""
      elide: Text.ElideRight
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    PanelActionButton {
      id: closeButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: Glyphs.close
      tooltipText: "Close"
      foreground: root.foreground
      fontFamily: root.fontFamily
      size: Style.space(24)
      onClicked: root.closeRequested()
    }
  }

  // ---------------------------------------------------------------- machine
  Card {
    foreground: root.foreground
    spacing: Style.space(6)

    SectionTitle { text: "Machine"; fontFamily: root.fontFamily }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: {
        var parts = []
        if (root.info.osName) parts.push(root.info.osName)
        if (root.info.cores > 0) parts.push(root.info.cores + " cores")
        parts.push(root.link ? root.link.status : "not sampling")
        return parts.join(" · ")
      }
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    FieldRow {
      label: "Name"

      TextField {
        id: nameField
        width: parent.width
        height: Style.space(26)
        text: root.machine ? (root.machine.alias || "") : ""
        placeholderText: root.isLocal && root.service ? root.service.localHostname : "Same as destination"
        foreground: root.foreground
        verticalPadding: Style.space(4)
        font.pixelSize: Style.font.bodySmall
        onEditingFinished: root.saveIdentity()
      }
    }

    FieldRow {
      visible: !root.isLocal
      label: "Destination"

      TextField {
        id: hostField
        width: parent.width
        height: Style.space(26)
        text: root.machine ? root.machine.host : ""
        placeholderText: "user@host or ssh alias"
        foreground: root.foreground
        verticalPadding: Style.space(4)
        font.pixelSize: Style.font.bodySmall
        onEditingFinished: root.saveIdentity()
      }
    }

    Text {
      id: identityError
      visible: text !== ""
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    FlagRow {
      label: "Show this machine"
      checked: !!root.machine && root.machine.enabled !== false
      onToggled: if (root.service) root.service.setMachineEnabled(root.machineId, !checked)
    }
  }

  // --------------------------------------------------------------- readouts
  Card {
    foreground: root.foreground
    spacing: Style.space(6)

    SectionTitle { text: "Readouts"; fontFamily: root.fontFamily }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: root.known
        ? "Shown on this machine's card, in this order. Each can show a mini graph, a ring, a figure, or a mix."
        : "Shown on this machine's card, in this order. Connect once to see which of these the machine has."
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Repeater {
      model: root.orderedModules.length

      delegate: Column {
        id: moduleRow
        required property int index
        readonly property string moduleId: String(root.orderedModules[index] || "")
        readonly property var def: Model.moduleDef(moduleId)
        readonly property int position: root.shownModules.indexOf(moduleId)
        readonly property bool on: position !== -1
        readonly property real indent: Style.space(12) + moduleSwitch.width + Style.space(12)

        width: parent.width
        spacing: Style.space(4)
        topPadding: Style.space(4)

        Item {
          width: parent.width
          height: Style.space(26)

          ToggleSwitch {
            id: moduleSwitch
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            checked: moduleRow.on
            trackHeight: Style.space(18)
            foreground: root.foreground
            onToggled: root.setModuleEnabled(moduleRow.moduleId, !moduleRow.on)
          }

          Text {
            textFormat: Text.PlainText
            anchors.left: moduleSwitch.right
            anchors.leftMargin: Style.space(12)
            anchors.right: reorder.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: moduleRow.def.label
            color: root.foreground
            opacity: moduleRow.on ? 1 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: moduleRow.on
            elide: Text.ElideRight
          }

          Row {
            id: reorder
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            visible: moduleRow.on

            PanelActionButton {
              iconText: Glyphs.moveUp
              tooltipText: "Move up on the card"
              enabled: moduleRow.position > 0
              foreground: root.foreground
              fontFamily: root.fontFamily
              size: Style.space(22)
              onClicked: root.moveModule(moduleRow.moduleId, -1)
            }

            PanelActionButton {
              iconText: Glyphs.moveDown
              tooltipText: "Move down on the card"
              enabled: moduleRow.position < root.shownModules.length - 1
              foreground: root.foreground
              fontFamily: root.fontFamily
              size: Style.space(22)
              onClicked: root.moveModule(moduleRow.moduleId, 1)
            }
          }
        }

        Dropdown {
          visible: moduleRow.on && (moduleRow.def.graph === true || moduleRow.def.ring === true)
          x: moduleRow.indent
          width: parent.width - x
          label: "Look"
          options: Model.styleOptions(moduleRow.moduleId)
          value: Model.machineStyle(root.machine, moduleRow.moduleId, root.defaultStyle)
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(value) { root.setStyle(moduleRow.moduleId, value) }
        }

        FlagRow {
          visible: moduleRow.on && moduleRow.moduleId === "gpu" && root.anyVram
          label: "Show VRAM"
          indent: moduleRow.indent
          checked: !!root.machine && root.machine.showGpuMemory === true
          onToggled: root.update({ showGpuMemory: checked ? null : true })
        }

        // Disks: a readout per device picked here, each showing transfer
        // speed, space used, or both.
        Column {
          visible: moduleRow.on && moduleRow.moduleId === "disks"
          x: moduleRow.indent
          width: parent.width - x
          spacing: 0

          Repeater {
            model: moduleRow.moduleId === "disks" ? root.diskOptions.length : 0

            delegate: Column {
              id: diskRow
              required property int index
              readonly property var option: root.diskOptions[index] || ({})
              readonly property string disk: String(option.value || "")
              readonly property int at: root.diskIndex(disk)
              width: parent.width
              spacing: 0

              FlagRow {
                label: String(diskRow.option.label || "")
                checked: diskRow.at !== -1
                onToggled: root.setDisk(diskRow.disk, !checked, "")
              }

              ChoiceRow {
                visible: diskRow.at !== -1
                indent: Style.space(14)
                label: "Show"
                options: Model.DISK_SHOWS
                value: diskRow.at !== -1 ? root.diskList[diskRow.at].show : "speed"
                onChanged: function(value) { root.setDisk(diskRow.disk, true, value) }
              }
            }
          }
        }

        // GPUs: which cards get a readout, on a machine with more than one.
        Column {
          visible: moduleRow.on && moduleRow.moduleId === "gpu" && root.gpuOptions.length > 1
          x: moduleRow.indent
          width: parent.width - x
          spacing: 0

          Repeater {
            model: moduleRow.moduleId === "gpu" ? root.gpuOptions.length : 0

            delegate: FlagRow {
              required property int index
              readonly property var gpu: root.gpuOptions[index] || ({})
              label: String(gpu.name || "GPU") + (gpu.util ? "" : " · no load")
              checked: root.gpuIds.indexOf(gpu.id) !== -1
              onToggled: root.setGpu(gpu.id, !checked)
            }
          }
        }

        // Sensors: every reading the card should carry.
        Column {
          visible: moduleRow.on && moduleRow.moduleId === "sensors"
          x: moduleRow.indent
          width: parent.width - x
          spacing: 0

          Repeater {
            model: moduleRow.moduleId === "sensors" ? root.sensorOptions.length : 0

            delegate: FlagRow {
              required property int index
              readonly property var option: root.sensorOptions[index] || ({})
              label: String(option.label || option.id || "")
              checked: root.sensorIds.indexOf(String(option.id)) !== -1
              onToggled: root.setSensor(String(option.id), !checked)
            }
          }

        }
      }
    }

    // What this machine can't show, and why.
    Repeater {
      model: root.unavailable

      delegate: Column {
        required property var modelData
        x: Style.space(12) + Style.space(36) + Style.space(12)
        width: parent.width - x
        topPadding: Style.space(4)
        spacing: Style.space(1)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: Model.moduleDef(modelData).label
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: Model.unavailableReason(modelData, root.info)
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Item {
      width: parent.width
      height: resetButton.implicitHeight + Style.space(4)

      Button {
        id: resetButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Reset to defaults"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: if (root.service) root.service.resetReadouts(root.machineId)
      }
    }
  }

  // ------------------------------------------------------------- all machines
  Card {
    foreground: root.foreground
    spacing: Style.space(6)

    SectionTitle { text: "All machines"; fontFamily: root.fontFamily }

    ChoiceRow {
      label: "Labels"
      options: [{ value: "text", label: "Letters" }, { value: "icon", label: "Icons" }]
      value: root.service ? root.service.labelMode : "text"
      onChanged: function(value) { if (root.service) root.service.setGlobal("barLabels", value) }
    }

    ChoiceRow {
      label: "Temperature"
      options: [{ value: "Celsius", label: "°C" }, { value: "Fahrenheit", label: "°F" }]
      value: root.service ? root.service.temperatureUnit : "Celsius"
      onChanged: function(value) { if (root.service) root.service.setGlobal("temperatureUnit", value) }
    }

    Dropdown {
      width: parent.width
      label: "Default look"
      options: [
        { value: "both", label: "Graph and figure" },
        { value: "graph", label: "Graph" },
        { value: "ring-text", label: "Ring and figure" },
        { value: "ring", label: "Ring" },
        { value: "text", label: "Figure" }
      ]
      value: root.defaultStyle
      foreground: root.foreground
      fontFamily: root.fontFamily
      onChanged: function(value) { if (root.service) root.service.setGlobal("style", value) }
    }
  }

  // ---------------------------------------------------------- components

  // Label on the left, switch on the right.
  component FlagRow: Item {
    id: flagRow

    property string label: ""
    property bool bold: false
    property bool checked: false
    property real indent: 0

    signal toggled()

    width: parent ? parent.width : implicitWidth
    height: Style.space(26)

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: flagRow.indent
      anchors.right: flagSwitch.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: flagRow.label
      color: root.foreground
      opacity: flagRow.checked ? 0.9 : 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: flagRow.bold
      elide: Text.ElideRight
    }

    ToggleSwitch {
      id: flagSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: flagRow.checked
      trackHeight: Style.space(18)
      foreground: root.foreground
      onToggled: flagRow.toggled()
    }

    MouseArea {
      anchors.fill: parent
      anchors.rightMargin: flagSwitch.width + Style.space(10)
      cursorShape: Qt.PointingHandCursor
      onClicked: flagRow.toggled()
    }
  }

  // Label on the left, a chip group on the right.
  component ChoiceRow: Item {
    id: choiceRow

    property string label: ""
    property var options: []
    property string value: ""
    property real indent: 0

    signal changed(string value)

    width: parent ? parent.width : implicitWidth
    height: Math.max(Style.space(30), chips.implicitHeight + Style.space(4))

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.leftMargin: choiceRow.indent
      anchors.right: chips.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: choiceRow.label
      color: root.foreground
      opacity: 0.9
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    ButtonGroup {
      id: chips
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      options: choiceRow.options
      value: choiceRow.value
      foreground: root.foreground
      background: Commons.Color.popups.background
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      focusable: false
      onChanged: function(value) { choiceRow.changed(value) }
    }
  }

  // Label above a full-width field.
  component FieldRow: Column {
    id: fieldRow
    property string label: ""
    default property alias content: holder.data

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(3)

    Text {
      textFormat: Text.PlainText
      text: fieldRow.label
      color: root.foreground
      opacity: 0.9
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Item {
      id: holder
      width: parent.width
      height: Style.space(26)
    }
  }
}
