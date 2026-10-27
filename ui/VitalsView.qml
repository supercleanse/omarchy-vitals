import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Glyphs.js" as Glyphs

// Everything inside the sidebar or window: a title row, then one card per
// enabled machine, or the machine list and editor while editing. Scrolls when
// the machines outgrow the screen.
Rectangle {
  id: root

  property var service: null
  // "left" or "right" draws a hairline on the edge facing the desktop; "" for
  // the window, which has its own frame.
  property string edge: ""
  property bool showClose: true
  // Window mode shows a machine's settings in place of the list; dock mode
  // opens them in a popout beside the sidebar instead.
  property bool inlineSettings: false

  readonly property color foreground: Commons.Color.bar.text
  readonly property color surface: Commons.Color.bar.background.a >= 0.9 ? Commons.Color.bar.background : Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Style.font.family
  readonly property real pad: Style.space(10)

  readonly property var machines: service ? service.machines : []
  readonly property var shown: machines.filter(function(m) { return m.enabled !== false })
  readonly property bool editing: !!service && service.editing
  readonly property bool settingsInline: inlineSettings && !!service && service.settingsId !== ""
  // Window mode: a readout click slides the machine's detail panel in over
  // the list, inside the window (a second window would be tiled and
  // reshuffle the desktop). Close or Escape returns to the list.
  readonly property bool detailInline: inlineSettings && !!service && service.detailId !== ""
  readonly property bool editorOpen: !!service && !!service.editor && !settingsInline
  readonly property int onlineCount: {
    if (!service) return 0
    var rev = service.linksRevision
    var n = 0
    for (var i = 0; i < shown.length; i++) {
      var link = service.linkFor(shown[i].id)
      if (link && (link.status === "online" || link.status === "stale")) n++
    }
    return n
  }

  color: surface

  TextMetrics {
    id: figureReserve
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    text: "100%"
  }

  TextMetrics {
    id: captionReserve
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    text: "52/128G"
  }

  readonly property real figureWidth: Math.ceil(Math.max(figureReserve.advanceWidth, captionReserve.advanceWidth))

  Rectangle {
    visible: root.edge !== ""
    width: 1
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: root.edge === "right" ? parent.left : undefined
    anchors.right: root.edge === "left" ? parent.right : undefined
    color: Util.alpha(root.foreground, 0.12)
  }

  Item {
    id: titleRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: root.pad
    anchors.rightMargin: Style.space(5)
    height: Style.space(32)

    Text {
      id: title
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.editing && !root.editorOpen ? "MACHINES" : "VITALS"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: Style.spaceReal(1.5)
      renderType: Text.NativeRendering
    }

    Text {
      anchors.left: title.right
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.editing && root.shown.length > 0
      textFormat: Text.PlainText
      text: root.onlineCount + "/" + root.shown.length
      color: Util.alpha(root.foreground, 0.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      IconButton {
        visible: !root.editing
        glyph: Glyphs.refresh
        color: root.foreground
        fontFamily: root.fontFamily
        glyphSize: Style.font.bodySmall
        onClicked: if (root.service) root.service.refresh()
      }

      IconButton {
        visible: !root.editorOpen
        glyph: root.editing ? Glyphs.check : Glyphs.pencil
        selected: root.editing
        color: root.foreground
        fontFamily: root.fontFamily
        glyphSize: Style.font.bodySmall
        onClicked: if (root.service) root.service.setEditing(!root.editing)
      }

      IconButton {
        visible: root.showClose
        glyph: Glyphs.close
        color: root.foreground
        fontFamily: root.fontFamily
        glyphSize: Style.font.bodySmall
        onClicked: if (root.service) root.service.hide()
      }
    }
  }

  Rectangle {
    id: rule
    anchors.top: titleRow.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: root.pad
    anchors.rightMargin: root.pad
    height: 1
    color: Util.alpha(root.foreground, 0.12)
  }

  Loader {
    id: inlineDetail
    anchors.top: rule.bottom
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    active: root.detailInline
    visible: active
    focus: active
    sourceComponent: DetailPanel {
      service: root.service
      foreground: root.foreground
      fontFamily: root.fontFamily
      focus: true
    }
  }

  Flickable {
    id: flick
    visible: !root.detailInline
    anchors.top: rule.bottom
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    clip: true
    contentWidth: width
    contentHeight: content.implicitHeight + Style.space(20)
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Column {
      id: content
      x: root.pad
      y: Style.space(10)
      width: flick.width - root.pad * 2
      spacing: Style.space(10)

      Text {
        visible: !!root.service && root.service.configError !== ""
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: root.service ? root.service.configError : ""
        color: root.service ? root.service.warn : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      // Monitoring view.
      Repeater {
        model: !root.editing && !root.editorOpen && !root.settingsInline ? root.shown : []

        delegate: Column {
          required property var modelData
          required property int index
          width: content.width
          spacing: Style.space(10)

          Rectangle {
            visible: index > 0
            width: parent.width
            height: 1
            color: Util.alpha(root.foreground, 0.08)
          }

          MachineCard {
            width: parent.width
            machine: modelData
            link: root.service ? root.service.linkFor(modelData.id) : null
            service: root.service
            foreground: root.foreground
            fontFamily: root.fontFamily
            figureWidth: root.figureWidth
          }
        }
      }

      Text {
        visible: !root.editing && !root.editorOpen && !root.settingsInline && root.shown.length === 0
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "No machines are switched on. Use the pencil to add or enable one."
        color: Util.alpha(root.foreground, 0.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      // Edit mode: the full list, including machines that are switched off.
      Repeater {
        model: root.editing && !root.editorOpen && !root.settingsInline ? root.machines : []

        delegate: EditRow {
          required property var modelData
          required property int index
          width: content.width
          machine: modelData
          position: index
          count: root.machines.length
          service: root.service
          foreground: root.foreground
          background: root.surface
          accent: root.accent
          fontFamily: root.fontFamily
        }
      }

      TextButton {
        visible: root.editing && !root.editorOpen && !root.settingsInline
        width: content.width
        text: "Add machine"
        glyph: Glyphs.plus
        color: root.foreground
        fontFamily: root.fontFamily
        enabled: !!root.service && root.service.configError === ""
        onClicked: if (root.service) root.service.openEditor("")
      }

      Text {
        visible: root.editing && !root.editorOpen && !root.settingsInline
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: "Saved in ~/.config/vitals/machines.json"
        color: Util.alpha(root.foreground, 0.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }

      Loader {
        active: root.settingsInline
        visible: active
        width: content.width
        sourceComponent: MachineSettings {
          width: content.width
          service: root.service
          machineId: root.service ? root.service.settingsId : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          onCloseRequested: if (root.service) root.service.closeSettings()
        }
      }

      MachineEditor {
        visible: root.editorOpen
        width: content.width
        service: root.service
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        fontFamily: root.fontFamily
      }
    }
  }

  // A thin scroll position marker, only while the list overflows.
  Rectangle {
    visible: flick.interactive && !root.detailInline
    anchors.right: parent.right
    anchors.rightMargin: 2
    y: flick.y + flick.visibleArea.yPosition * flick.height
    width: 3
    height: Math.max(Style.space(16), flick.visibleArea.heightRatio * flick.height)
    radius: 1.5
    color: Util.alpha(root.foreground, 0.25)
  }
}
