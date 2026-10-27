import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Model.js" as Model
import "../omastats/Model.js" as Oma
import "../omastats/ui" as OmaUi
import "Glyphs.js" as Glyphs

// One machine's detail panel: OmaStats' panel, with the machine's name on
// top. The tab strip, pages, cards, graphs, rings and process lists are
// OmaStats' own (vendored under omastats/, MIT); this file only frames them
// and gives them the `host` they expect (close, and the expandable,
// searchable process list).
Item {
  id: root

  property var service: null
  property color foreground: Commons.Color.popups.text
  property string fontFamily: Style.font.family
  property real padding: Style.spacing.popupPadding

  readonly property string machineId: service ? service.detailId : ""
  readonly property var machine: {
    var list = service ? service.machines : []
    for (var i = 0; i < list.length; i++) if (list[i].id === machineId) return list[i]
    return null
  }
  readonly property var link: service ? service.linkFor(machineId) : null
  readonly property var info: link && link.info ? link.info : ({})
  readonly property var source: service ? service.detail : null
  readonly property var tabs: Model.detailTabs(info)
  readonly property string currentTab: service ? service.detailTab : "cpu"
  readonly property string alias: machine ? Model.displayAlias(machine, service ? service.localHostname : "") : ""
  readonly property string linkStatus: link ? link.status : "idle"

  // The `host` API OmaStats' pages and process list use.
  property bool processesExpanded: false
  property string processQuery: ""
  property bool searchActive: false
  property var searchField: null
  readonly property var bar: null

  function setProcessesExpanded(value) {
    processesExpanded = value === true
    if (!processesExpanded) { processQuery = ""; searchActive = false }
    if (service) service.detailAll = processesExpanded
  }

  function close() { if (service) service.closeDetail() }

  function cycleTab(delta) {
    if (tabs.length === 0 || !service) return
    var at = tabs.indexOf(currentTab)
    service.setDetailTab(tabs[(at + delta + tabs.length) % tabs.length])
  }

  onMachineIdChanged: setProcessesExpanded(false)
  onCurrentTabChanged: { setProcessesExpanded(false); flick.contentY = 0 }

  // Disk traffic per process needs readable per-process I/O counters; a
  // machine that reports none gets no process list on the Disks page.
  // Per-process GPU use needs root everywhere, so the GPU page never shows
  // a process list.
  readonly property var pageSettings: ({
    showProcesses: currentTab !== "gpu"
      && !(currentTab === "disks" && !(source && source.snapshot && source.snapshot.procs && source.snapshot.procs.io !== undefined))
  })

  readonly property real contentHeight: header.height + tabStrip.height + Style.space(10) + statusLine.height + pageLoader.implicitHeight + padding * 2
  implicitWidth: Math.max(Style.space(372), Math.ceil(tabStrip.spelledWidth) + padding * 2)
  implicitHeight: contentHeight

  focus: true
  Keys.onEscapePressed: root.close()
  Keys.onLeftPressed: if (!root.searchActive) root.cycleTab(-1)
  Keys.onRightPressed: if (!root.searchActive) root.cycleTab(1)

  Item {
    id: header
    x: root.padding
    y: root.padding
    width: root.width - root.padding * 2
    height: Style.space(30)

    Rectangle {
      id: dot
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: width
      radius: width / 2
      color: !root.service ? root.foreground
        : (root.linkStatus === "online" ? root.service.good
        : (root.linkStatus === "offline" ? root.service.danger : root.service.warn))
    }

    Text {
      id: title
      anchors.left: dot.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width - closeButton.width - Style.space(60))
      textFormat: Text.PlainText
      text: root.alias
      elide: Text.ElideRight
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      anchors.left: title.right
      anchors.leftMargin: Style.space(8)
      anchors.right: closeButton.left
      anchors.rightMargin: Style.space(8)
      anchors.baseline: title.baseline
      textFormat: Text.PlainText
      text: {
        var parts = []
        if (root.info.osName) parts.push(root.info.osName)
        if (root.machine && root.machine.host) parts.push(root.machine.host)
        return parts.join(" · ")
      }
      elide: Text.ElideRight
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
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
      onClicked: root.close()
    }
  }

  OmaUi.ModuleTabs {
    id: tabStrip
    anchors.top: header.bottom
    anchors.topMargin: Style.space(6)
    x: root.padding
    width: root.width - root.padding * 2
    tabs: root.tabs
    settingsTab: "settings"
    current: root.currentTab
    foreground: root.foreground
    fontFamily: root.fontFamily
    onActivated: function(id) { if (root.service) root.service.setDetailTab(id) }
  }

  Text {
    id: statusLine
    anchors.top: tabStrip.bottom
    x: root.padding
    width: root.width - root.padding * 2
    textFormat: Text.PlainText
    readonly property string message: {
      if (root.linkStatus === "offline") return root.alias + " is offline · reconnecting"
      if (!root.source || !root.source.ready) return root.source && root.source.status === "offline" ? "Reconnecting…" : "Collecting details…"
      return ""
    }
    visible: message !== ""
    height: visible ? Math.ceil(font.pixelSize * 1.5) + Style.space(10) : 0
    verticalAlignment: Text.AlignBottom
    text: message
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  Flickable {
    id: flick
    anchors.top: statusLine.bottom
    anchors.topMargin: Style.space(10)
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.padding
    x: root.padding
    width: root.width - root.padding * 2
    clip: true
    contentWidth: width
    contentHeight: pageLoader.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    Loader {
      id: pageLoader
      width: flick.width
      active: !!root.source && root.source.ready && root.tabs.indexOf(root.currentTab) !== -1
      source: Qt.resolvedUrl("../omastats/ui/" + Oma.pageFile(root.currentTab))
    }

    Binding { target: pageLoader.item; property: "service"; value: root.source; when: pageLoader.status === Loader.Ready }
    Binding { target: pageLoader.item; property: "settings"; value: root.pageSettings; when: pageLoader.status === Loader.Ready }
    Binding { target: pageLoader.item; property: "host"; value: root; when: pageLoader.status === Loader.Ready }
    Binding { target: pageLoader.item; property: "temperatureUnit"; value: root.service ? root.service.temperatureUnit : "Celsius"; when: pageLoader.status === Loader.Ready }
    Binding { target: pageLoader.item; property: "publicIpEnabled"; value: false; when: pageLoader.status === Loader.Ready }
    Binding { target: pageLoader.item; property: "foreground"; value: root.foreground; when: pageLoader.status === Loader.Ready }
    Binding { target: pageLoader.item; property: "fontFamily"; value: root.fontFamily; when: pageLoader.status === Loader.Ready }
  }

  // The same thin scroll marker as the sidebar.
  Rectangle {
    visible: flick.interactive
    anchors.right: parent.right
    anchors.rightMargin: 3
    y: flick.y + flick.visibleArea.yPosition * flick.height
    width: 3
    height: Math.max(Style.space(16), flick.visibleArea.heightRatio * flick.height)
    radius: 1.5
    color: Util.alpha(root.foreground, 0.25)
  }
}
