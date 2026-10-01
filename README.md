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
- Sends optional desktop notifications for newly seen incidents and critical escalations after the initial refresh, aggregating large bursts.
- Exposes status, applications, incidents, filtering, refresh, and triage
  actions through Omarchy Shell IPC.
- Reuses the CLI's OAuth credential store and never prints, copies, or persists
  tokens.

## Requirements

- Omarchy with Quickshell plugin support.
- [AppSignal CLI](https://github.com/appsignal/appsignal-cli).
- An authenticated AppSignal CLI session.

Install the CLI by following the [official AppSignal CLI installation instructions](https://github.com/appsignal/appsignal-cli#installation), then authenticate it:

```bash
appsignal-cli auth login
appsignal-cli apps list
```

## Installation

From a remote Git repository:

```bash
omarchy plugin add https://github.com/gregmolnar/omarchy-appsignal-plugin.git --enable
```

From this checkout:

```bash
omarchy plugin add ~/git/omarchy-appsignal-plugin --enable
```

The plugin ID is `gregmolnar.appsignal`, and its default bar section is the right side.

## Removal

```bash
omarchy plugin remove gregmolnar.appsignal
```

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

Limit monitored applications with the plugin's comma-separated `appIds` setting. Leaving it blank monitors all discovered applications up to `maxApps`. Incident notifications can be disabled with the `notificationsEnabled` setting.

## IPC

```bash
omarchy-shell gregmolnar.appsignal status
omarchy-shell gregmolnar.appsignal apps
omarchy-shell gregmolnar.appsignal incidents
omarchy-shell gregmolnar.appsignal refresh
omarchy-shell gregmolnar.appsignal selectApp '<app-id>'
omarchy-shell gregmolnar.appsignal markWip '<app-id>' <incident-number>
omarchy-shell gregmolnar.appsignal closeIncident '<app-id>' <incident-number>
omarchy-shell gregmolnar.appsignal assignMe '<app-id>' <incident-number>
omarchy-shell gregmolnar.appsignal open
omarchy-shell gregmolnar.appsignal close
omarchy-shell gregmolnar.appsignal toggle
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

Application and incident data remain in the Quickshell process memory. The plugin does not write monitoring data or credentials to disk. Every AppSignal CLI invocation runs through `appsignal-cli-bounded`, which stops it after 20 seconds and caps stdout at 1 MiB and stderr at 64 KiB before either stream reaches Quickshell's collectors.

Desktop alerts are sent through Omarchy's built-in `omarchy-notification-send` command. Provider-controlled notification text is length-limited and escaped before being passed as a discrete argument. Notification delivery is capped at five seconds, the first successful refresh establishes a silent baseline, and bursts of more than five new or newly critical incidents produce one aggregate alert.

To identify which WIP incidents belong to you, `appsignal-current-user` reads
the OAuth access token from the AppSignal CLI configuration and requests only
`viewer { id name email }` from AppSignal GraphQL. The token is kept in process
memory and is never printed, copied, or passed as a command-line argument. The
normal CLI request runs first so expired OAuth credentials are refreshed before
this query.

## License

MIT
