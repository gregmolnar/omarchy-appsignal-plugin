import QtQuick
import QtTest
import Quickshell.Io
import "../.."

TestCase {
  name: "AppSignalService"
  property var service: null

  Component { id: serviceComponent; Service {} }

  function init() {
    service = serviceComponent.createObject(this)
    verify(service !== null)
  }

  function cleanup() {
    service.destroy()
    service = null
  }

  function processFor(parts) {
    for (var i = 0; i < ProcessRegistry.processes.length; i++) {
      var process = ProcessRegistry.processes[i]
      for (var start = 0; start <= process.command.length - parts.length; start++) {
        var matches = true
        for (var p = 0; p < parts.length; p++) {
          if (process.command[start + p] !== parts[p]) matches = false
        }
        if (matches) return process
      }
    }
    return null
  }

  function argumentAfter(process, name) {
    var index = process.command.indexOf(name)
    return index >= 0 ? process.command[index + 1] : undefined
  }

  function test_refresh_fetches_apps_org_and_incidents() {
    service.refresh()
    var apps = processFor(["--output", "json", "apps", "list"])
    verify(apps !== null)
    apps.complete(0, JSON.stringify({ apps: [
      { id: "one", name: "API", environment: "production" },
      { id: "two", name: "Worker", environment: "production" }
    ] }), "")

    var user = processFor(["/usr/bin/env", "python3"])
    verify(user !== null)
    user.complete(0, '{"user":{"id":"user-1","name":"Ada","email":"ada@example.com"}}', "")

    var org = processFor(["--output", "json", "apps", "show-org"])
    verify(org !== null)
    org.complete(0, '{"org":"acme","message":"ok"}', "")

    var incidents = processFor(["--output", "json", "incidents", "list"])
    verify(incidents !== null)
    compare(argumentAfter(incidents, "--app-id"), "one")
    incidents.complete(0, JSON.stringify({ incidents: [{
      __typename: "ExceptionIncident", id: "e1", number: 1,
      state: "OPEN", severity: "CRITICAL", count: 2,
      exceptionName: "Boom"
    }] }), "")

    compare(argumentAfter(incidents, "--app-id"), "one")
    compare(argumentAfter(incidents, "--state"), "WIP")
    incidents.complete(0, JSON.stringify({ incidents: [
      { __typename: "ExceptionIncident", id: "mine", number: 3,
        state: "WIP", severity: "LOW", count: 1,
        exceptionName: "Mine", assignees: [{ id: "user-1", name: "Ada" }] },
      { __typename: "ExceptionIncident", id: "theirs", number: 4,
        state: "WIP", severity: "HIGH", count: 1,
        exceptionName: "Theirs", assignees: [{ id: "user-2", name: "Grace" }] }
    ] }), "")

    compare(argumentAfter(incidents, "--app-id"), "two")
    compare(argumentAfter(incidents, "--state"), "OPEN")
    incidents.complete(0, JSON.stringify({ incidents: [{
      __typename: "PerformanceIncident", id: "p1", number: 2,
      state: "OPEN", severity: "HIGH", count: 1,
      actionNames: ["POST /jobs"]
    }] }), "")

    compare(argumentAfter(incidents, "--app-id"), "two")
    compare(argumentAfter(incidents, "--state"), "WIP")
    incidents.complete(0, '{"incidents":[]}', "")

    compare(service.refreshing, false)
    compare(service.organization, "acme")
    compare(service.currentUser.id, "user-1")
    compare(service.appCount, 2)
    compare(service.openCount, 2)
    compare(service.wipCount, 1)
    compare(service.criticalCount, 1)
    compare(service.incidents.some(function(item) { return item.id === "mine" }), true)
    compare(service.incidents.some(function(item) { return item.id === "theirs" }), false)
  }

  function incident() {
    return {
      id: "e1", number: 42, appId: "one", appLabel: "API · production",
      title: "Boom", state: "OPEN", severity: "CRITICAL", timestampMs: 1,
      assignees: [], assigneeIds: []
    }
  }

  function test_notifications_skip_initial_results_and_report_new_incidents() {
    var existing = incident()
    service.updateIncidentNotifications([existing])
    compare(processFor(["omarchy-notification-send"]), null)

    var fresh = incident()
    fresh.id = "e2"
    fresh.number = 43
    fresh.title = "<img src=https://example.com/tracker>"
    service.updateIncidentNotifications([existing, fresh])

    var notification = processFor(["omarchy-notification-send"])
    verify(notification !== null)
    compare(notification.command[0], "/usr/bin/timeout")
    compare(argumentAfter(notification, "--urgency"), "critical")
    verify(notification.command[notification.command.length - 1].indexOf("&lt;img") !== -1)
    verify(notification.command[notification.command.length - 1].indexOf("<img") === -1)
  }

  function test_notifications_can_be_disabled() {
    service.settings = { notificationsEnabled: false }
    var existing = incident()
    service.updateIncidentNotifications([existing])
    var fresh = incident()
    fresh.id = "e2"
    service.updateIncidentNotifications([existing, fresh])
    compare(processFor(["omarchy-notification-send"]), null)
  }

  function test_wip_action_assigns_me_and_keeps_item_after_success() {
    var item = incident()
    service.incidents = [item]
    service.currentUser = { id: "user-1", name: "Ada", email: "ada@example.com" }
    service.updateCounts()

    compare(service.updateState(item, "WIP"), "started")
    compare(service.actionRunning, true)
    var action = processFor(["--output", "json", "incidents", "update"])
    verify(action !== null)
    compare(action.command.slice(3).join(" "),
      "--output json incidents update --number 42 --app-id one --state WIP --assign-me")

    action.complete(0, '{"incident":{"number":42,"state":"WIP"}}', "")
    compare(service.actionRunning, false)
    compare(service.actionStatus, "Assigned incident #42 to you as WIP")
    compare(service.incidents.length, 1)
    compare(service.incidents[0].state, "WIP")
    compare(service.incidents[0].assigneeIds[0], "user-1")
    compare(service.openCount, 0)
    compare(service.wipCount, 1)
  }

  function test_assign_me_uses_cli_and_keeps_item_in_open_feed() {
    var item = incident()
    service.incidents = [item]

    compare(service.assignMe(item), "started")
    var action = processFor(["--output", "json", "incidents", "update"])
    verify(action !== null)
    compare(action.command.slice(3).join(" "),
      "--output json incidents update --number 42 --app-id one --assign-me")

    action.complete(0, '{"incident":{"number":42}}', "")
    compare(service.actionStatus, "Assigned incident #42 to you")
    compare(service.incidents.length, 1)
  }

  function test_action_failure_preserves_item_and_surfaces_error() {
    var item = incident()
    service.incidents = [item]

    service.updateState(item, "CLOSED")
    var action = processFor(["--output", "json", "incidents", "update"])
    action.complete(1, "", "Permission denied")

    compare(service.actionRunning, false)
    compare(service.incidents.length, 1)
    compare(service.lastError, "Permission denied")
    compare(service.actionStatus, "Permission denied")
  }

  function test_missing_cli_reports_installation_error() {
    service.refresh()
    var apps = processFor(["--output", "json", "apps", "list"])
    verify(apps !== null)
    apps.complete(127, "", "appsignal-cli: command not found")
    compare(service.refreshing, false)
    compare(service.installed, false)
    verify(service.lastError.indexOf("not found") !== -1)
  }
}
