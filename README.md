# AppSignal for Omarchy

An *unofficial* Omarchy bar plugin for monitoring open AppSignal incidents across applications.

## Current features

- Discovers applications through the official AppSignal CLI.
- Shows open, assigned WIP, and critical incident counts in the bar.
- Displays WIP incidents only when they are assigned to the authenticated CLI
  user, with a prominent `MY WIP` badge that includes severity when one has been
  selected.
- Combines incidents from multiple applications.
- Filters by application or critical severity.
- Supports exception, performance, anomaly, and log incidents.
- Opens incidents in AppSignal.
- Takes ownership and marks incidents as WIP, closes them, or assigns them to
  the authenticated user.
- Confirms destructive close actions in the panel.
- Polls periodically and refreshes on right-click or middle-click.
- Exposes status, applications, incidents, filtering, refresh, and triage
  actions through Omarchy Shell IPC.
- Reuses the CLI's OAuth credential store and never prints, copies, or persists
  tokens.

## Requirements

- Omarchy with Quickshell plugin support.
- [AppSignal CLI](https://github.com/appsignal/appsignal-cli).
- An authenticated AppSignal CLI session.

Install and authenticate the CLI:

```bash
curl -sSL https://github.com/appsignal/appsignal-cli/releases/latest/download/install.sh | sudo sh
appsignal-cli auth login
appsignal-cli apps list
```

## Installation

From a remote Git repository:

```bash
omarchy plugin add https://github.com/YOUR-ACCOUNT/omarchy-appsignal-plugin.git --enable
```

From this checkout:

```bash
omarchy plugin add ~/git/omarchy-appsignal-plugin --enable
```

The plugin ID is `appsignal.status`, and its default bar section is the right side.

## Usage

- Left-click the icon to open or close the incident panel.
- Right-click or middle-click to refresh.
- Select an application to filter incidents.
- Press Up/Down to select an incident and Enter to open it.
- Press Left/Right to cycle application filters.
- Press `C` for critical incidents, `A` for all open incidents, or `R` to refresh.
- With an incident selected, press `W` to assign it to yourself and mark it WIP, `M` to assign it to yourself, or `X` to close it.
- Assigned WIP incidents remain in the panel until you close them.
- Closing an incident requires confirmation.

Limit monitored applications with the plugin's comma-separated `appIds` setting. Leaving it blank monitors all discovered applications up to `maxApps`.

## IPC

```bash
omarchy-shell appsignal.status status
omarchy-shell appsignal.status apps
omarchy-shell appsignal.status incidents
omarchy-shell appsignal.status refresh
omarchy-shell appsignal.status selectApp '<app-id>'
omarchy-shell appsignal.status markWip '<app-id>' <incident-number>
omarchy-shell appsignal.status closeIncident '<app-id>' <incident-number>
omarchy-shell appsignal.status assignMe '<app-id>' <incident-number>
omarchy-shell appsignal.status open
omarchy-shell appsignal.status close
omarchy-shell appsignal.status toggle
```

`status`, `apps`, and `incidents` return JSON.

## Development

Run model and QML service tests:

```bash
./tests/run
```

## Privacy and security

Authentication is done via the appsignal-cli and the plugin uses the appsignal-cli to interact with the AppSignal API by running these local commands:

```text
appsignal-cli --output json apps list
appsignal-cli --output json apps show-org
appsignal-cli --output json incidents list --app-id <id> --state OPEN --order LAST --limit <count>
appsignal-cli --output json incidents list --app-id <id> --state WIP --order LAST --limit <count>
appsignal-cli --output json incidents update --number <number> --app-id <id> --state WIP --assign-me
appsignal-cli --output json incidents update --number <number> --app-id <id> --state CLOSED
appsignal-cli --output json incidents update --number <number> --app-id <id> --assign-me
```

Application and incident data remain in the Quickshell process memory. The plugin does not write monitoring data or credentials to disk.

To identify which WIP incidents belong to you, `appsignal-current-user` reads
the OAuth access token from the AppSignal CLI configuration and requests only
`viewer { id name email }` from AppSignal GraphQL. The token is kept in process
memory and is never printed, copied, or passed as a command-line argument. The
normal CLI request runs first so expired OAuth credentials are refreshed before
this query.

## License

MIT
