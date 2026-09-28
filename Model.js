function cleanText(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/\s+/g, " ")
    .trim()
}

function parseJson(raw, subject) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "AppSignal CLI returned no " + subject }
  try {
    var value = JSON.parse(text)
    if (!value || typeof value !== "object") throw new Error("invalid")
    if (value.error) return { ok: false, error: cleanText(value.error.message || value.error) }
    return { ok: true, value: value }
  } catch (error) {
    return { ok: false, error: "Could not parse AppSignal CLI " + subject }
  }
}

function parseOrganization(raw) {
  var result = parseJson(raw, "organization data")
  if (!result.ok) return { ok: false, error: result.error, organization: "" }
  return {
    ok: true,
    error: "",
    organization: cleanText(result.value.org || result.value.organization || "")
  }
}

function parseCurrentUser(raw) {
  var result = parseJson(raw, "current-user data")
  if (!result.ok) return { ok: false, error: result.error, user: null }
  var value = result.value.user || {}
  var id = cleanText(value.id)
  if (id === "") return { ok: false, error: "AppSignal returned no authenticated user", user: null }
  return {
    ok: true,
    error: "",
    user: { id: id, name: cleanText(value.name), email: cleanText(value.email) }
  }
}

function parseApps(raw, allowedIds, limit) {
  var result = parseJson(raw, "application data")
  if (!result.ok) return { ok: false, error: result.error, apps: [] }
  var source = Array.isArray(result.value.apps) ? result.value.apps : []
  var allowed = {}
  var ids = String(allowedIds || "").split(",")
  for (var i = 0; i < ids.length; i++) {
    var allowedId = ids[i].trim()
    if (allowedId !== "") allowed[allowedId] = true
  }
  var filtered = Object.keys(allowed).length > 0
  var apps = []
  for (var index = 0; index < source.length; index++) {
    var item = source[index] || {}
    var id = cleanText(item.id)
    if (id === "" || (filtered && !allowed[id])) continue
    var name = cleanText(item.name) || "App " + id
    var environment = cleanText(item.environment)
    apps.push({
      id: id,
      name: name,
      environment: environment,
      label: environment === "" ? name : name + " · " + environment,
      order: apps.length
    })
  }
  apps.sort(function(a, b) {
    return a.label.toLowerCase().localeCompare(b.label.toLowerCase())
  })
  var maximum = positiveInteger(limit, 10)
  if (apps.length > maximum) apps = apps.slice(0, maximum)
  for (var position = 0; position < apps.length; position++) apps[position].order = position
  return { ok: true, error: "", apps: apps }
}

function incidentKind(value) {
  var type = cleanText(value).replace(/Incident$/, "")
  if (type === "Exception") return "exception"
  if (type === "Performance") return "performance"
  if (type === "Anomaly") return "anomaly"
  if (type === "Log") return "log"
  return type.toLowerCase() || "incident"
}

function incidentTitle(item, kind) {
  if (kind === "exception") return cleanText(item.exceptionName) || "Exception incident"
  if (kind === "performance") {
    var actions = Array.isArray(item.actionNames) ? item.actionNames : []
    return cleanText(actions[0] || item.description) || "Performance incident"
  }
  if (kind === "anomaly") {
    return cleanText(item.trigger && item.trigger.name ? item.trigger.name : item.description) || "Anomaly incident"
  }
  return cleanText(item.description) || (kind === "log" ? "Log incident" : "AppSignal incident")
}

function parseIncidents(raw, app) {
  var result = parseJson(raw, "incident data")
  if (!result.ok) return { ok: false, error: result.error, incidents: [] }
  var source = Array.isArray(result.value.incidents) ? result.value.incidents : []
  var incidents = []
  for (var index = 0; index < source.length; index++) {
    var item = source[index] || {}
    var id = cleanText(item.id)
    var number = parseInt(String(item.number), 10)
    if (id === "" || !isFinite(number)) continue
    var kind = incidentKind(item.__typename)
    var timestamp = cleanText(item.lastOccurredAt || item.updatedAt || item.createdAt)
    var timestampMs = Date.parse(timestamp)
    if (!isFinite(timestampMs)) timestampMs = 0
    var assignees = []
    var rawAssignees = Array.isArray(item.assignees) ? item.assignees : []
    for (var assigneeIndex = 0; assigneeIndex < rawAssignees.length; assigneeIndex++) {
      var name = cleanText(rawAssignees[assigneeIndex] && rawAssignees[assigneeIndex].name)
      if (name !== "") assignees.push(name)
    }
    incidents.push({
      id: id,
      number: number,
      appId: cleanText(app.id),
      appName: cleanText(app.name),
      appEnvironment: cleanText(app.environment),
      appLabel: cleanText(app.label),
      appOrder: Number(app.order || 0),
      kind: kind,
      title: incidentTitle(item, kind),
      detail: cleanText(item.exceptionMessage || item.description || ""),
      state: cleanText(item.state).toUpperCase() || "OPEN",
      severity: cleanText(item.severity).toUpperCase() || "UNTRIAGED",
      namespace: cleanText(item.namespace),
      count: Math.max(0, parseInt(String(item.count || 0), 10) || 0),
      assignees: assignees,
      assigneeIds: rawAssignees.map(function(assignee) { return cleanText(assignee && assignee.id) }).filter(function(id) { return id !== "" }),
      timestamp: timestamp,
      timestampMs: timestampMs
    })
  }
  return { ok: true, error: "", incidents: incidents }
}

function severityRank(severity) {
  var value = cleanText(severity).toUpperCase()
  if (value === "CRITICAL") return 0
  if (value === "HIGH") return 1
  if (value === "UNTRIAGED") return 2
  if (value === "LOW") return 3
  if (value === "INFORMATIONAL") return 4
  return 5
}

function sortIncidents(items) {
  var sorted = Array.isArray(items) ? items.slice() : []
  sorted.sort(function(a, b) {
    var stateA = a.state === "OPEN" ? 0 : 1
    var stateB = b.state === "OPEN" ? 0 : 1
    if (stateA !== stateB) return stateA - stateB
    var severityDifference = severityRank(a.severity) - severityRank(b.severity)
    if (severityDifference !== 0) return severityDifference
    var timeDifference = Number(b.timestampMs || 0) - Number(a.timestampMs || 0)
    if (timeDifference !== 0) return timeDifference
    return String(a.id).localeCompare(String(b.id))
  })
  return sorted
}

function assignedToUser(item, userId) {
  var id = cleanText(userId)
  if (id === "" || !item || !Array.isArray(item.assigneeIds)) return false
  return item.assigneeIds.indexOf(id) !== -1
}

function filterAssignedTo(items, userId) {
  return (Array.isArray(items) ? items : []).filter(function(item) {
    return assignedToUser(item, userId)
  })
}

function filterIncidents(items, appId, severity) {
  var selectedApp = cleanText(appId)
  var selectedSeverity = cleanText(severity).toUpperCase()
  return (Array.isArray(items) ? items : []).filter(function(item) {
    if (selectedApp !== "" && item.appId !== selectedApp) return false
    if (selectedSeverity !== "" && item.severity !== selectedSeverity) return false
    return true
  })
}

function appFilterOptions(apps) {
  var options = [{ value: "", label: "All applications" }]
  var source = Array.isArray(apps) ? apps : []
  for (var i = 0; i < source.length; i++) options.push({ value: source[i].id, label: source[i].label })
  return options
}

function incidentUrl(organization, item) {
  if (!item) return ""
  var org = encodeURIComponent(cleanText(organization))
  var appId = encodeURIComponent(cleanText(item.appId))
  var number = encodeURIComponent(String(item.number || ""))
  if (org === "" || appId === "" || number === "") return ""
  var area = item.kind === "exception" ? "exceptions"
    : item.kind === "performance" ? "performance"
    : item.kind === "anomaly" ? "anomalies"
    : item.kind === "log" ? "logs" : "incidents"
  return "https://appsignal.com/" + org + "/sites/" + appId + "/" + area + "/incidents/" + number
}

function relativeTime(timestampMs, nowMs) {
  var value = Number(timestampMs || 0)
  if (!isFinite(value) || value <= 0) return ""
  var difference = Math.max(0, Number(nowMs === undefined ? Date.now() : nowMs) - value)
  var minutes = Math.floor(difference / 60000)
  if (minutes < 1) return "just now"
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  return days + "d ago"
}

function incidentBadge(item, userId) {
  if (!item) return ""
  var severity = cleanText(item.severity).toUpperCase() || "UNTRIAGED"
  if (item.state === "WIP" && assignedToUser(item, userId)) {
    return severity === "UNTRIAGED" ? "MY WIP" : "MY WIP · " + severity
  }
  return severity
}

function incidentMeta(item, nowMs, showApp) {
  if (!item) return ""
  var parts = []
  var age = relativeTime(item.timestampMs, nowMs)
  if (age !== "") parts.push(age)
  if (item.count > 0) parts.push(item.count + (item.count === 1 ? " occurrence" : " occurrences"))
  if (item.state === "WIP") parts.push("WIP")
  if (item.namespace !== "") parts.push(item.namespace)
  if (Array.isArray(item.assignees) && item.assignees.length > 0) parts.push("Assigned: " + item.assignees.join(", "))
  if (showApp && item.appLabel !== "") parts.push(item.appLabel)
  return parts.join(" • ")
}

function positiveInteger(value, fallback) {
  var number = parseInt(String(value), 10)
  return isFinite(number) && number > 0 ? number : fallback
}

if (typeof module !== "undefined") {
  module.exports = {
    cleanText: cleanText,
    parseOrganization: parseOrganization,
    parseCurrentUser: parseCurrentUser,
    parseApps: parseApps,
    parseIncidents: parseIncidents,
    sortIncidents: sortIncidents,
    assignedToUser: assignedToUser,
    filterAssignedTo: filterAssignedTo,
    filterIncidents: filterIncidents,
    appFilterOptions: appFilterOptions,
    incidentUrl: incidentUrl,
    relativeTime: relativeTime,
    incidentBadge: incidentBadge,
    incidentMeta: incidentMeta,
    severityRank: severityRank
  }
}
