const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const app = {
  id: "site-1",
  name: "Checkout",
  environment: "production",
  label: "Checkout · production",
  order: 0
}

test("parseCurrentUser normalizes the authenticated viewer", () => {
  assert.deepEqual(Model.parseCurrentUser(JSON.stringify({ user: {
    id: "user-1", name: "Ada", email: "ada@example.com"
  } })), {
    ok: true, error: "", user: { id: "user-1", name: "Ada", email: "ada@example.com" }
  })
})

test("parseApps filters configured IDs, sorts, and labels environments", () => {
  const result = Model.parseApps(JSON.stringify({ apps: [
    { id: "site-2", name: "Worker", environment: "staging" },
    { id: "site-1", name: "Checkout", environment: "production" },
    { id: "site-3", name: "Ignored", environment: "production" }
  ] }), "site-2, site-1", 10)

  assert.equal(result.ok, true)
  assert.deepEqual(result.apps.map(item => item.id), ["site-1", "site-2"])
  assert.equal(result.apps[0].label, "Checkout · production")
})

test("parseIncidents normalizes every incident type", () => {
  const result = Model.parseIncidents(JSON.stringify({ incidents: [
    {
      __typename: "ExceptionIncident",
      id: "e1",
      number: 42,
      state: "OPEN",
      severity: "CRITICAL",
      count: 8,
      lastOccurredAt: "2025-09-22T10:00:00Z",
      exceptionName: "NoMethodError",
      exceptionMessage: "undefined method call",
      namespace: "web",
      assignees: [{ name: "Ada" }]
    },
    {
      __typename: "PerformanceIncident",
      id: "p1",
      number: 43,
      state: "WIP",
      severity: "HIGH",
      count: 2,
      actionNames: ["POST /checkout"]
    },
    {
      __typename: "AnomalyIncident",
      id: "a1",
      number: 44,
      state: "OPEN",
      count: 1,
      trigger: { name: "High error rate" }
    }
  ] }), app)

  assert.equal(result.ok, true)
  assert.deepEqual(result.incidents.map(item => item.kind), ["exception", "performance", "anomaly"])
  assert.equal(result.incidents[0].title, "NoMethodError")
  assert.equal(result.incidents[0].detail, "undefined method call")
  assert.deepEqual(result.incidents[0].assignees, ["Ada"])
  assert.deepEqual(result.incidents[0].assigneeIds, [])
  assert.equal(result.incidents[1].title, "POST /checkout")
  assert.equal(result.incidents[2].title, "High error rate")
})

test("sortIncidents prioritizes open state, severity, then recency", () => {
  const sorted = Model.sortIncidents([
    { id: "wip", state: "WIP", severity: "CRITICAL", timestampMs: 9 },
    { id: "high", state: "OPEN", severity: "HIGH", timestampMs: 8 },
    { id: "old-critical", state: "OPEN", severity: "CRITICAL", timestampMs: 1 },
    { id: "new-critical", state: "OPEN", severity: "CRITICAL", timestampMs: 10 }
  ])
  assert.deepEqual(sorted.map(item => item.id), ["new-critical", "old-critical", "high", "wip"])
})

test("WIP filtering matches assignee IDs, not display names", () => {
  const items = [
    { id: "mine", assigneeIds: ["user-1"], assignees: ["Ada"] },
    { id: "theirs", assigneeIds: ["user-2"], assignees: ["Ada"] },
    { id: "unassigned", assigneeIds: [] }
  ]
  assert.deepEqual(Model.filterAssignedTo(items, "user-1").map(item => item.id), ["mine"])
})

test("filters combine app and severity", () => {
  const items = [
    { id: "a", appId: "one", severity: "CRITICAL" },
    { id: "b", appId: "one", severity: "HIGH" },
    { id: "c", appId: "two", severity: "CRITICAL" }
  ]
  assert.deepEqual(Model.filterIncidents(items, "one", "CRITICAL").map(item => item.id), ["a"])
})

test("incident badges clearly identify my WIP while retaining severity", () => {
  assert.equal(Model.incidentBadge({
    state: "WIP", severity: "HIGH", assigneeIds: ["user-1"]
  }, "user-1"), "MY WIP · HIGH")
  assert.equal(Model.incidentBadge({
    state: "WIP", severity: "UNTRIAGED", assigneeIds: ["user-1"]
  }, "user-1"), "MY WIP")
  assert.equal(Model.incidentBadge({
    state: "WIP", severity: "LOW", assigneeIds: ["user-2"]
  }, "user-1"), "LOW")
  assert.equal(Model.incidentBadge({
    state: "OPEN", severity: "CRITICAL", assigneeIds: ["user-1"]
  }, "user-1"), "CRITICAL")
})

test("incident metadata includes assignees", () => {
  assert.equal(Model.incidentMeta({
    timestampMs: 0, count: 2, namespace: "web",
    assignees: ["Ada"], appLabel: "API · production"
  }, 0, true), "2 occurrences • web • Assigned: Ada • API · production")
  assert.equal(Model.incidentMeta({
    timestampMs: 0, count: 1, namespace: "", state: "WIP",
    assignees: ["Ada"], appLabel: ""
  }, 0, false), "1 occurrence • WIP • Assigned: Ada")
})

test("incidentUrl maps incident kinds to AppSignal areas", () => {
  assert.equal(
    Model.incidentUrl("acme", { appId: "site-1", number: 42, kind: "exception" }),
    "https://appsignal.com/acme/sites/site-1/exceptions/incidents/42"
  )
  assert.equal(Model.incidentUrl("", { appId: "site-1", number: 42 }), "")
})

test("organization and invalid output parsing are explicit", () => {
  assert.deepEqual(Model.parseOrganization('{"org":"acme","message":"ok"}'), {
    ok: true, error: "", organization: "acme"
  })
  assert.deepEqual(Model.parseApps("not json", "", 10), {
    ok: false, error: "Could not parse AppSignal CLI application data", apps: []
  })
})
