import QtQuick
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool refreshing: false
  property bool installed: true
  property bool authenticated: true
  property string organization: ""
  property var currentUser: null
  property var apps: []
  property var incidents: []
  property int openCount: 0
  property int wipCount: 0
  property int criticalCount: 0
  property date lastUpdated: new Date(0)
  property string lastError: ""
  property bool actionRunning: false
  property string actionStatus: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 60, 3600)
  readonly property int maxApps: intSetting("maxApps", 10, 1, 50)
  readonly property int maxPerApp: intSetting("maxPerApp", 10, 5, 50)
  readonly property bool notificationsEnabled: boolSetting("notificationsEnabled", true)
  readonly property string appIds: String(setting("appIds", ""))
  readonly property int appCount: apps.length

  property string _appsOutput: ""
  property string _appsError: ""
  property string _orgOutput: ""
  property string _orgError: ""
  property string _userOutput: ""
  property string _userError: ""
  property var _fetchApps: []
  property var _fetchStates: []
  property var _fetchedIncidents: []
  property int _fetchIndex: 0
  property int _fetchStateIndex: 0
  property var _currentApp: null
  property string _currentState: "OPEN"
  property string _incidentsOutput: ""
  property string _incidentsError: ""
  property var _partialErrors: []
  property var _actionIncident: null
  property string _actionKind: ""
  property string _actionValue: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property bool _incidentFetchFailed: false
  property bool _notificationBaselineReady: false
  property var _incidentSnapshot: ({})
  property var _notificationQueue: []

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "boolean") return value
    return String(value).toLowerCase() !== "false"
  }

  function conciseError(value, fallback) {
    var text = String(value || fallback || "AppSignal request failed").replace(/\s+/g, " ").trim()
    return text.length > 180 ? text.substring(0, 177) + "…" : text
  }

  function helperPath(name) {
    var value = String(Qt.resolvedUrl(name))
    if (value.indexOf("file://") === 0) value = value.substring(7)
    return decodeURIComponent(value)
  }

  function cliCommand(args) {
    return ["/usr/bin/env", "python3", helperPath("appsignal-cli-bounded")].concat(args)
  }

  function incidentKey(item) {
    return String(item.appId || "") + ":" + String(item.id || "")
  }

  function notificationText(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }

  function queueDesktopNotification(headline, description, critical) {
    _notificationQueue.push([
      "/usr/bin/timeout", "--kill-after=1s", "5s",
      "omarchy-notification-send",
      "--app-name", "AppSignal",
      "--urgency", critical ? "critical" : "normal",
      "--expire-time", "10000",
      headline, notificationText(description)
    ])
    runNextNotification()
  }

  function queueIncidentNotification(item, escalated) {
    var critical = item.severity === "CRITICAL"
    var headline = escalated ? "AppSignal incident became critical"
      : critical ? "New critical AppSignal incident" : "New AppSignal incident"
    var description = conciseError(
      String(item.appLabel || "AppSignal") + " · #" + item.number + " · " + String(item.title || "Incident"),
      "Open AppSignal incident")
    queueDesktopNotification(headline, description, critical)
  }

  function runNextNotification() {
    if (notificationProcess.running || _notificationQueue.length === 0) return
    notificationProcess.command = _notificationQueue.shift()
    notificationProcess.running = true
  }

  function updateIncidentNotifications(items) {
    var next = ({})
    var notifications = []
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      var key = incidentKey(item)
      next[key] = { state: String(item.state || ""), severity: String(item.severity || "") }
      if (!_notificationBaselineReady) continue
      var previous = _incidentSnapshot[key]
      var escalated = previous !== undefined
        && item.severity === "CRITICAL"
        && previous.severity !== "CRITICAL"
      if (previous === undefined || escalated) notifications.push({ item: item, escalated: escalated })
    }
    _incidentSnapshot = next
    if (!_notificationBaselineReady) {
      _notificationBaselineReady = true
      return
    }
    if (!notificationsEnabled) return
    if (notifications.length > 5) {
      var criticalCount = 0
      for (var c = 0; c < notifications.length; c++) {
        if (notifications[c].item.severity === "CRITICAL") criticalCount++
      }
      queueDesktopNotification(
        notifications.length + " new AppSignal incidents",
        criticalCount > 0 ? criticalCount + " critical incidents need attention" : "Open the AppSignal panel to review them",
        criticalCount > 0)
      return
    }
    for (var n = 0; n < notifications.length; n++) {
      queueIncidentNotification(notifications[n].item, notifications[n].escalated)
    }
  }

  function refreshIfStale() {
    var updatedAt = lastUpdated instanceof Date ? lastUpdated.getTime() : 0
    if (updatedAt <= 0 || Date.now() - updatedAt >= refreshIntervalSec * 1000) refresh()
  }

  function refresh() {
    if (refreshing || actionRunning || appsProcess.running || currentUserProcess.running || organizationProcess.running || incidentsProcess.running) return
    refreshing = true
    installed = true
    authenticated = true
    lastError = ""
    _partialErrors = []
    _appsOutput = ""
    _appsError = ""
    appsProcess.command = cliCommand(["--output", "json", "apps", "list"])
    appsProcess.running = true
  }

  function fetchCurrentUser() {
    _userOutput = ""
    _userError = ""
    currentUserProcess.command = ["/usr/bin/env", "python3", helperPath("appsignal-current-user")]
    currentUserProcess.running = true
  }

  function fetchOrganization() {
    _orgOutput = ""
    _orgError = ""
    organizationProcess.command = cliCommand(["--output", "json", "apps", "show-org"])
    organizationProcess.running = true
  }

  function beginIncidentFetch(nextApps) {
    _fetchApps = nextApps
    _fetchStates = currentUser && currentUser.id ? ["OPEN", "WIP"] : ["OPEN"]
    _fetchedIncidents = []
    _incidentFetchFailed = false
    _fetchIndex = 0
    _fetchStateIndex = 0
    fetchNextAppState()
  }

  function fetchNextAppState() {
    if (_fetchIndex >= _fetchApps.length) {
      finishRefresh()
      return
    }
    _currentApp = _fetchApps[_fetchIndex]
    _currentState = _fetchStates[_fetchStateIndex]
    _incidentsOutput = ""
    _incidentsError = ""
    incidentsProcess.command = cliCommand([
      "--output", "json", "incidents", "list",
      "--app-id", String(_currentApp.id),
      "--state", _currentState,
      "--order", "LAST",
      "--limit", String(maxPerApp)
    ])
    incidentsProcess.running = true
  }

  function advanceIncidentFetch() {
    _fetchStateIndex++
    if (_fetchStateIndex >= _fetchStates.length) {
      _fetchStateIndex = 0
      _fetchIndex++
    }
    fetchNextAppState()
  }

  function updateCounts() {
    var open = 0
    var wip = 0
    var critical = 0
    for (var i = 0; i < incidents.length; i++) {
      if (incidents[i].state === "OPEN") open++
      if (incidents[i].state === "WIP") wip++
      if (incidents[i].severity === "CRITICAL") critical++
    }
    openCount = open
    wipCount = wip
    criticalCount = critical
  }

  function finishRefresh() {
    incidents = Model.sortIncidents(_fetchedIncidents)
    if (!_incidentFetchFailed) updateIncidentNotifications(incidents)
    updateCounts()
    refreshing = false
    lastUpdated = new Date()
    lastError = _partialErrors.length > 0 ? _partialErrors.join(" · ") : ""
  }

  function findIncident(appId, number) {
    for (var i = 0; i < incidents.length; i++) {
      if (incidents[i].appId === String(appId) && incidents[i].number === Number(number)) return incidents[i]
    }
    return null
  }

  function updateState(item, state) {
    var nextState = String(state || "").toUpperCase()
    if (!item || (nextState !== "WIP" && nextState !== "CLOSED")) return "invalid"
    return startAction(item, "state", nextState)
  }

  function assignMe(item) {
    if (!item) return "invalid"
    return startAction(item, "assign", "")
  }

  function startAction(item, kind, value) {
    if (refreshing || actionRunning) return "busy"
    _actionIncident = item
    _actionKind = kind
    _actionValue = value
    _actionOutput = ""
    _actionError = ""
    lastError = ""
    actionStatusTimer.stop()
    actionRunning = true

    var command = cliCommand([
      "--output", "json", "incidents", "update",
      "--number", String(item.number),
      "--app-id", String(item.appId)
    ])
    if (kind === "assign") {
      command.push("--assign-me")
      actionStatus = "Assigning incident #" + item.number + " to you…"
    } else {
      command.push("--state")
      command.push(value)
      if (value === "WIP") command.push("--assign-me")
      actionStatus = (value === "CLOSED" ? "Closing" : "Taking ownership of") + " incident #" + item.number + "…"
    }
    actionProcess.command = command
    actionProcess.running = true
    return "started"
  }

  function removeFromFeed(item) {
    var next = []
    for (var i = 0; i < incidents.length; i++) {
      if (incidents[i].id !== item.id || incidents[i].appId !== item.appId) next.push(incidents[i])
    }
    incidents = next
    updateCounts()
  }

  function moveToMyWip(item) {
    var next = []
    for (var i = 0; i < incidents.length; i++) {
      var existing = incidents[i]
      if (existing.id === item.id && existing.appId === item.appId) {
        var replacement = {}
        for (var key in existing) replacement[key] = existing[key]
        replacement.state = "WIP"
        replacement.assigneeIds = Array.isArray(existing.assigneeIds) ? existing.assigneeIds.slice() : []
        replacement.assignees = Array.isArray(existing.assignees) ? existing.assignees.slice() : []
        if (currentUser && replacement.assigneeIds.indexOf(currentUser.id) === -1) {
          replacement.assigneeIds.push(currentUser.id)
          replacement.assignees.push(currentUser.name || currentUser.email || "You")
        }
        next.push(replacement)
      } else next.push(existing)
    }
    incidents = Model.sortIncidents(next)
    updateCounts()
  }

  function finishAction(exitCode, stdout, stderr) {
    var item = _actionIncident
    var kind = _actionKind
    var value = _actionValue
    actionRunning = false
    if (exitCode !== 0) {
      lastError = conciseError(stderr || stdout, "Could not update incident")
      actionStatus = lastError
      actionStatusTimer.restart()
      return
    }

    if (kind === "assign") actionStatus = "Assigned incident #" + item.number + " to you"
    else {
      actionStatus = value === "CLOSED"
        ? "Closed incident #" + item.number
        : "Assigned incident #" + item.number + " to you as WIP"
      if (value === "CLOSED") removeFromFeed(item)
      else moveToMyWip(item)
    }
    actionStatusTimer.restart()
    Qt.callLater(function() { root.refresh() })
  }

  Timer {
    id: actionStatusTimer
    interval: 3000
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: appsProcess
    running: false
    command: []
    stdout: StdioCollector { id: appsStdout; waitForEnd: true; onStreamFinished: root._appsOutput = text }
    stderr: StdioCollector { id: appsStderr; waitForEnd: true; onStreamFinished: root._appsError = text }
    onExited: function(exitCode) {
      var stdout = String(appsStdout.text || root._appsOutput || "")
      var stderr = String(appsStderr.text || root._appsError || "")
      if (exitCode !== 0) {
        root.installed = exitCode !== 127
        root.authenticated = !/not authenticated|auth login|unauthorized|oauth/i.test(stderr + " " + stdout)
        root.lastError = root.conciseError(stderr || stdout,
          root.installed ? "Could not list AppSignal applications" : "AppSignal CLI is not installed")
        root.refreshing = false
        return
      }
      var parsed = Model.parseApps(stdout, root.appIds, root.maxApps)
      if (!parsed.ok) {
        root.lastError = parsed.error
        root.refreshing = false
        return
      }
      root.apps = parsed.apps
      root.fetchCurrentUser()
    }
  }

  Process {
    id: currentUserProcess
    running: false
    command: []
    stdout: StdioCollector { id: userStdout; waitForEnd: true; onStreamFinished: root._userOutput = text }
    stderr: StdioCollector { id: userStderr; waitForEnd: true; onStreamFinished: root._userError = text }
    onExited: function(exitCode) {
      var stdout = String(userStdout.text || root._userOutput || "")
      var stderr = String(userStderr.text || root._userError || "")
      root.currentUser = null
      if (exitCode === 0) {
        var parsed = Model.parseCurrentUser(stdout)
        if (parsed.ok) root.currentUser = parsed.user
        else root._partialErrors.push(parsed.error)
      } else {
        root._partialErrors.push(root.conciseError(stderr || stdout, "Could not determine the authenticated user; WIP incidents are hidden"))
      }
      root.fetchOrganization()
    }
  }

  Process {
    id: organizationProcess
    running: false
    command: []
    stdout: StdioCollector { id: orgStdout; waitForEnd: true; onStreamFinished: root._orgOutput = text }
    stderr: StdioCollector { id: orgStderr; waitForEnd: true; onStreamFinished: root._orgError = text }
    onExited: function(exitCode) {
      var stdout = String(orgStdout.text || root._orgOutput || "")
      var stderr = String(orgStderr.text || root._orgError || "")
      if (exitCode === 0) {
        var parsed = Model.parseOrganization(stdout)
        if (parsed.ok) root.organization = parsed.organization
        else root._partialErrors.push(parsed.error)
      } else {
        root._partialErrors.push(root.conciseError(stderr || stdout, "Could not determine organization"))
      }
      root.beginIncidentFetch(root.apps)
    }
  }

  Process {
    id: incidentsProcess
    running: false
    command: []
    stdout: StdioCollector { id: incidentsStdout; waitForEnd: true; onStreamFinished: root._incidentsOutput = text }
    stderr: StdioCollector { id: incidentsStderr; waitForEnd: true; onStreamFinished: root._incidentsError = text }
    onExited: function(exitCode) {
      var app = root._currentApp
      var stdout = String(incidentsStdout.text || root._incidentsOutput || "")
      var stderr = String(incidentsStderr.text || root._incidentsError || "")
      if (exitCode === 0) {
        var parsed = Model.parseIncidents(stdout, app)
        if (parsed.ok) {
          var fetched = parsed.incidents
          if (root._currentState === "WIP") fetched = Model.filterAssignedTo(fetched, root.currentUser.id)
          root._fetchedIncidents = root._fetchedIncidents.concat(fetched)
        } else {
          root._incidentFetchFailed = true
          root._partialErrors.push(app.label + " " + root._currentState + ": " + parsed.error)
        }
      } else {
        root._incidentFetchFailed = true
        root._partialErrors.push(app.label + " " + root._currentState + ": " + root.conciseError(stderr || stdout, "request failed"))
      }
      root.advanceIncidentFetch()
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      root.finishAction(
        exitCode,
        String(actionStdout.text || root._actionOutput || ""),
        String(actionStderr.text || root._actionError || ""))
    }
  }

  Process {
    id: notificationProcess
    running: false
    command: []
    onExited: root.runNextNotification()
  }
}
