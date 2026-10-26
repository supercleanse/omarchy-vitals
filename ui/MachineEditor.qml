import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Glyphs.js" as Glyphs

// Add or edit one machine: a name and an SSH destination. The local machine
// only takes a name.
Item {
  id: root

  property var service: null
  property var draft: service ? service.editor : null
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  readonly property bool isLocal: !!draft && draft.id === "local"
  readonly property bool isNew: !!draft && !draft.id
  property string error: ""

  function save() {
    if (!service) return
    error = service.saveEditor({
      id: draft ? draft.id : "",
      alias: aliasField.text,
      host: root.isLocal ? "" : hostField.text,
      enabled: enabledCheck.checked
    }) || ""
  }

  onDraftChanged: {
    error = ""
    if (!draft) return
    aliasField.text = draft.alias || ""
    hostField.text = draft.host || ""
    enabledCheck.checked = draft.enabled !== false
    Qt.callLater(function() { (root.isLocal || !root.isNew ? aliasField : hostField).input.forceActiveFocus() })
  }

  implicitHeight: form.implicitHeight

  Keys.onEscapePressed: if (service) service.closeEditor()

  Column {
    id: form
    width: parent.width
    spacing: Style.space(12)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.isNew ? "Add machine" : (root.isLocal ? "This machine" : "Edit machine")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      renderType: Text.NativeRendering
    }

    Field {
      id: hostField
      visible: !root.isLocal
      width: parent.width
      label: "SSH DESTINATION"
      placeholder: "studio-mini or user@host"
      hint: "An ssh_config alias, Tailscale name or user@host. Key login must already work."
      color: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onAccepted: root.save()
    }

    Field {
      id: aliasField
      width: parent.width
      label: "NAME"
      placeholder: root.isLocal ? (root.service ? root.service.localHostname : "") : "Same as destination"
      hint: root.isLocal ? "Leave empty to use the hostname." : ""
      color: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onAccepted: root.save()
    }

    Row {
      spacing: Style.space(7)

      Check {
        id: enabledCheck
        anchors.verticalCenter: parent.verticalCenter
        color: root.foreground
        accent: root.accent
        background: root.background
        fontFamily: root.fontFamily
        onToggled: function(value) { checked = value }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Enabled"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
        MouseArea { anchors.fill: parent; onClicked: enabledCheck.checked = !enabledCheck.checked }
      }
    }

    Text {
      visible: root.error !== ""
      width: parent.width
      textFormat: Text.PlainText
      text: root.error
      wrapMode: Text.WordWrap
      color: root.service ? root.service.danger : Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
    }

    Row {
      anchors.right: parent.right
      spacing: Style.space(6)

      TextButton {
        text: "Cancel"
        color: root.foreground
        fontFamily: root.fontFamily
        onClicked: if (root.service) root.service.closeEditor()
      }

      TextButton {
        text: root.isNew ? "Add" : "Save"
        glyph: Glyphs.check
        primary: true
        color: root.foreground
        accent: root.accent
        background: root.background
        fontFamily: root.fontFamily
        onClicked: root.save()
      }
    }
  }
}
