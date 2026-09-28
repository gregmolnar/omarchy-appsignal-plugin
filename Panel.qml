import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "gregmolnar.appsignal"
  ipcTarget: "gregmolnar.appsignal"
  manageIpc: false

  property int selectedIndex: 0
  property bool cursorActive: false
  property double nowMs: Date.now()
  property string appFilter: ""
  property string severityFilter: ""
  property var pendingCloseIncident: null
  property bool closeConfirmOpen: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var filteredIncidents: Model.filterIncidents(service.incidents, appFilter, severityFilter)
  readonly property var appOptions: Model.appFilterOptions(service.apps)
  readonly property bool otherAppsOpen: {
    if (appFilter === "") return false
    for (var i = 0; i < service.incidents.length; i++) {
      if (service.incidents[i].appId !== appFilter
          && (service.incidents[i].state === "OPEN" || service.incidents[i].state === "WIP")) return true
    }
    return false
  }

  readonly property string heroStatus: {
    if (service.actionStatus !== "") return service.actionStatus
    if (service.lastError !== "") return service.lastError
    if (service.refreshing) return "Checking application health…"
    if (!service.installed) return "AppSignal CLI is not installed"
    if (!service.authenticated) return "Run appsignal-cli auth login"
    if (service.openCount === 0 && service.wipCount === 0) return "All monitored applications are healthy"
    if (service.criticalCount > 0) return service.criticalCount + " critical · " + service.openCount + " open · " + service.wipCount + " my WIP"
    if (service.openCount === 0) return service.wipCount + (service.wipCount === 1 ? " incident assigned to me" : " incidents assigned to me")
    return service.openCount + " open · " + service.wipCount + " my WIP"
  }

  function resetView() {
    selectedIndex = 0
    cursorActive = false
    pointerGate.reset()
    if (panelFlick) panelFlick.contentY = 0
  }

  function setAppFilter(value) {
    appFilter = String(value || "")
    resetView()
  }

  function setSeverityFilter(value) {
    severityFilter = String(value || "")
    resetView()
  }

  function ensureAppFilter() {
    if (appFilter === "") return
    for (var i = 0; i < service.apps.length; i++) if (service.apps[i].id === appFilter) return
    setAppFilter("")
  }

  function ensureSelection() {
    if (filteredIncidents.length === 0) selectedIndex = 0
    else selectedIndex = Math.max(0, Math.min(filteredIncidents.length - 1, selectedIndex))
  }

  function select(index) {
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(filteredIncidents.length - 1, index))
    scrollSelectionIntoView()
  }

  function moveSelection(delta) {
    if (filteredIncidents.length === 0) return
    if (!cursorActive) select(0)
    else select(selectedIndex + delta)
  }

  function cycleApp(delta) {
    if (appOptions.length < 2) return
    var current = 0
    for (var i = 0; i < appOptions.length; i++) if (appOptions[i].value === appFilter) current = i
    setAppFilter(appOptions[(current + delta + appOptions.length) % appOptions.length].value)
  }

  function selectedIncident() {
    if (!cursorActive || filteredIncidents.length === 0) return null
    return filteredIncidents[selectedIndex]
  }

  function activateSelection() {
    var item = selectedIncident()
    if (item) openIncident(item)
  }

  function markSelectedWip() {
    var item = selectedIncident()
    if (item && item.state !== "WIP") service.updateState(item, "WIP")
  }

  function assignSelectedToMe() {
    var item = selectedIncident()
    if (item) service.assignMe(item)
  }

  function requestClose(item) {
    if (!item || service.actionRunning || service.refreshing) return
    pendingCloseIncident = item
    closeConfirm.selectedIndex = 1
    closeConfirmOpen = true
  }

  function cancelClose() {
    closeConfirmOpen = false
    pendingCloseIncident = null
  }

  function confirmClose() {
    var item = pendingCloseIncident
    closeConfirmOpen = false
    pendingCloseIncident = null
    if (item) service.updateState(item, "CLOSED")
  }

  function openIncident(item) {
    var url = Model.incidentUrl(service.organization, item)
    if (url !== "") Qt.openUrlExternally(url)
  }

  function scrollSelectionIntoView() {
    if (!incidentColumn || selectedIndex < 0 || selectedIndex >= incidentColumn.children.length) return
    var wrapper = incidentColumn.children[selectedIndex]
    Qt.callLater(function() {
      if (!wrapper || !panelFlick) return
      var point = wrapper.mapToItem(panelFlick.contentItem, 0, 0)
      var margin = Style.space(8)
      var top = point.y
      var bottom = top + wrapper.height
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(Math.max(0, panelFlick.contentHeight - panelFlick.height), bottom + margin - panelFlick.height)
    })
  }

  function severityColor(value) {
    var severity = String(value || "").toUpperCase()
    if (severity === "CRITICAL") return urgent
    if (severity === "HIGH") return Color.accent
    return dim
  }

  function incidentBadgeColor(item) {
    if (item.severity === "CRITICAL") return urgent
    if (item.state === "WIP") return Color.accent
    return severityColor(item.severity)
  }

  function kindIcon(kind) {
    if (kind === "exception") return "󰅚"
    if (kind === "performance") return "󰓅"
    if (kind === "anomaly") return "󰀦"
    if (kind === "log") return "󰌱"
    return "󰋼"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    service.refreshIfStale()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onFilteredIncidentsChanged: ensureSelection()

  PointerMoveGate { id: pointerGate; referenceItem: panelFlick }

  Service {
    id: service
    settings: root.settings
    onAppsChanged: root.ensureAppFilter()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(); return "ok" }
    function selectApp(appId: string): string { root.setAppFilter(appId); return "ok" }
    function markWip(appId: string, number: int): string {
      return service.updateState(service.findIncident(appId, number), "WIP")
    }
    function closeIncident(appId: string, number: int): string {
      return service.updateState(service.findIncident(appId, number), "CLOSED")
    }
    function assignMe(appId: string, number: int): string {
      return service.assignMe(service.findIncident(appId, number))
    }
    function apps(): string { return JSON.stringify(service.apps) }
    function incidents(): string { return JSON.stringify(root.filteredIncidents) }
    function status(): string {
      return JSON.stringify({
        installed: service.installed,
        authenticated: service.authenticated,
        organization: service.organization,
        applications: service.appCount,
        openIncidents: service.openCount,
        myWipIncidents: service.wipCount,
        criticalIncidents: service.criticalCount,
        currentUser: service.currentUser ? { id: service.currentUser.id, name: service.currentUser.name } : null,
        visibleIncidents: root.filteredIncidents.length,
        selectedApp: root.appFilter,
        refreshing: service.refreshing,
        actionRunning: service.actionRunning,
        actionStatus: service.actionStatus,
        lastUpdated: service.lastUpdated.toISOString(),
        error: service.lastError
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        AppSignalIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: service.criticalCount > 0 ? root.urgent
            : service.openCount > 0 || service.wipCount > 0 ? Color.accent : root.foreground
        }
      }
    }
    tooltipText: service.refreshing ? "Refreshing AppSignal"
      : service.openCount + " open · " + service.wipCount + " assigned WIP"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) service.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(fixedContent.implicitHeight + incidentContent.implicitHeight + Style.space(12), Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: appDropdown.popupOpen
      onMoveRequested: function(dx, dy) {
        if (root.closeConfirmOpen) {
          closeConfirm.selectedIndex = closeConfirm.selectedIndex === 0 ? 1 : 0
        } else if (dx !== 0) root.cycleApp(dx)
        else if (dy !== 0) root.moveSelection(dy)
      }
      onActivateRequested: {
        if (root.closeConfirmOpen) {
          if (closeConfirm.selectedIndex === 0) root.cancelClose()
          else root.confirmClose()
        } else root.activateSelection()
      }
      onCloseRequested: {
        if (root.closeConfirmOpen) root.cancelClose()
        else root.close()
      }
      onDeleteRequested: {
        if (!root.closeConfirmOpen) root.requestClose(root.selectedIncident())
      }
      onTabRequested: function(direction) {
        if (root.closeConfirmOpen) closeConfirm.selectedIndex = closeConfirm.selectedIndex === 0 ? 1 : 0
        else root.switchPanel(direction)
      }
      onTextKey: function(text) {
        if (root.closeConfirmOpen) return
        if (text === "r" || text === "R") service.refresh()
        else if (text === "c" || text === "C") root.setSeverityFilter("CRITICAL")
        else if (text === "a" || text === "A") root.setSeverityFilter("")
        else if (text === "w" || text === "W") root.markSelectedWip()
        else if (text === "m" || text === "M") root.assignSelectedToMe()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(12)

        Column {
          id: fixedContent
          Layout.fillWidth: true
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, refreshButton.implicitHeight)

            AppSignalIcon {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconSize: Style.font.display
              color: service.criticalCount > 0 ? root.urgent : root.foreground
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                text: "AppSignal"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                width: parent.width
                text: root.heroStatus.toUpperCase()
                textFormat: Text.PlainText
                color: service.lastError !== "" || service.criticalCount > 0 ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: service.refreshing ? "󰑓" : "󰑐"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !service.refreshing && !service.actionRunning
              onClicked: service.refresh()
            }
          }

          PanelSeparator { foreground: root.foreground }

          Dropdown {
            id: appDropdown
            visible: service.appCount > 1
            width: parent.width
            showLabel: false
            options: root.appOptions
            foreground: root.foreground
            background: Color.popups.background
            accent: Color.accent
            fontFamily: root.fontFamily
            onChanged: function(value) { root.setAppFilter(value) }
            Binding on value { value: root.appFilter }

            Rectangle {
              visible: root.appFilter !== "" && root.otherAppsOpen
              x: parent.width - width / 2
              y: -height / 2
              width: Style.space(8)
              height: width
              radius: width / 2
              color: root.urgent
            }
          }

          Row {
            spacing: Style.space(2)
            Button {
              text: "ACTIVE"
              selected: root.severityFilter === ""
              foreground: root.foreground
              background: "transparent"
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(1)
              onClicked: root.setSeverityFilter("")
            }
            Button {
              text: "CRITICAL"
              selected: root.severityFilter === "CRITICAL"
              foreground: root.foreground
              background: "transparent"
              accent: root.urgent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(1)
              onClicked: root.setSeverityFilter("CRITICAL")
            }
          }
        }

        Flickable {
          id: panelFlick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: incidentContent.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: incidentContent
            width: panelFlick.width
            spacing: Style.space(12)

            Text {
              visible: !service.refreshing && root.filteredIncidents.length === 0 && service.lastError === ""
              width: parent.width
              text: root.severityFilter === "CRITICAL" ? "No critical incidents." : "No open or assigned WIP incidents."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              topPadding: Style.space(16)
              bottomPadding: Style.space(18)
            }

            Column {
              id: incidentColumn
              visible: root.filteredIncidents.length > 0
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: root.filteredIncidents

                CursorSurface {
                  id: incidentRow
                  required property var modelData
                  required property int index
                  width: incidentColumn.width
                  foreground: root.foreground
                  hasCursor: root.cursorActive && root.selectedIndex === index
                  implicitHeight: rowContent.implicitHeight + Style.space(16)

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) {
                      if (pointerGate.moved(incidentRow, mouse)) root.select(incidentRow.index)
                    }
                    onClicked: root.openIncident(incidentRow.modelData)
                  }

                  PanelToolTip {
                    visible: rowMouse.containsMouse
                    text: "Open incident #" + incidentRow.modelData.number + " in AppSignal"
                    fontFamily: root.fontFamily
                  }

                  RowLayout {
                    id: rowContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(9)

                    Text {
                      Layout.preferredWidth: Style.space(24)
                      Layout.alignment: Qt.AlignTop
                      text: root.kindIcon(incidentRow.modelData.kind)
                      color: root.severityColor(incidentRow.modelData.severity)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                      horizontalAlignment: Text.AlignHCenter
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: Style.space(2)
                      Text {
                        Layout.fillWidth: true
                        text: incidentRow.modelData.title
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.weight: incidentRow.modelData.severity === "CRITICAL" ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                      }
                      Text {
                        visible: incidentRow.modelData.detail !== "" && incidentRow.modelData.detail !== incidentRow.modelData.title
                        Layout.fillWidth: true
                        text: incidentRow.modelData.detail
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                      }
                      Text {
                        Layout.fillWidth: true
                        text: Model.incidentMeta(incidentRow.modelData, root.nowMs, root.appFilter === "")
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Row {
                      Layout.alignment: Qt.AlignTop
                      spacing: Style.space(1)

                      PanelActionButton {
                        iconText: "󰓾"
                        tooltipText: Model.assignedToUser(incidentRow.modelData, service.currentUser ? service.currentUser.id : "") ? "Assigned to you" : "Assign to me"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        enabled: !service.actionRunning && !service.refreshing
                          && !Model.assignedToUser(incidentRow.modelData, service.currentUser ? service.currentUser.id : "")
                        onClicked: service.assignMe(incidentRow.modelData)
                      }

                      PanelActionButton {
                        iconText: "󰏫"
                        tooltipText: "Take ownership and mark WIP"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        enabled: !service.actionRunning && !service.refreshing && incidentRow.modelData.state !== "WIP"
                        onClicked: service.updateState(incidentRow.modelData, "WIP")
                      }

                      PanelActionButton {
                        iconText: "󰅖"
                        tooltipText: "Close incident"
                        foreground: root.foreground
                        hoverColor: root.urgent
                        fontFamily: root.fontFamily
                        enabled: !service.actionRunning && !service.refreshing
                        onClicked: root.requestClose(incidentRow.modelData)
                      }
                    }

                    Rectangle {
                      Layout.alignment: Qt.AlignTop
                      Layout.preferredHeight: Style.space(16)
                      Layout.preferredWidth: Math.max(Style.space(34), severityText.implicitWidth + Style.space(10))
                      radius: Style.space(8)
                      color: root.incidentBadgeColor(incidentRow.modelData)
                      Text {
                        id: severityText
                        anchors.centerIn: parent
                        text: Model.incidentBadge(
                          incidentRow.modelData,
                          service.currentUser ? service.currentUser.id : "")
                        textFormat: Text.PlainText
                        color: Color.popups.background
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      ConfirmDialog {
        id: closeConfirm
        anchors.fill: parent
        opened: root.closeConfirmOpen
        z: 10
        message: root.pendingCloseIncident
          ? "Close incident #" + root.pendingCloseIncident.number + "?"
          : "Close incident?"
        confirmText: "Close"
        background: Color.popups.background
        foreground: root.foreground
        selectedText: root.urgent
        fontFamily: root.fontFamily
        onCanceled: root.cancelClose()
        onConfirmed: root.confirmClose()
      }
    }
  }
}
