# redmine_kalvad_slack

[![lint](https://github.com/KalvadTech/redmine-slack/actions/workflows/lint.yml/badge.svg)](https://github.com/KalvadTech/redmine-slack/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Redmine](https://img.shields.io/badge/Redmine-%E2%89%A56.1-c61b1b.svg)](https://www.redmine.org/)

Slack incoming-webhook notifications for Redmine 6.x.

A focused, opinionated rewrite inspired by
[`alphanodes/redmine_messenger`](https://github.com/alphanodes/redmine_messenger).
Slack only, Redmine 6 only, zero extra runtime gem dependencies, fire-and-forget
delivery. Configuration is fully per-project: there is no global plugin
settings page.

## Features

- Posts on issue created, updated, closed, wiki page created or updated, news.
- Color-coded Slack `attachments` payload (green, blue, grey, purple, yellow).
- Each project has its own `Settings -> Slack` tab. No global config.
- Per-project webhook URL, channel, posted-as username, and icon.
- Per-event boolean toggles, plus privacy gates for private issues and
  private notes.
- @mentions: extracts `@username` from issue descriptions and journal notes,
  appends them to the Slack message so mentioned users are notified.
- Slack user mentions in assignee fields: when a user has a `Slack Userid`
  custom field set, their assignment triggers a real `<@SLACK_ID>` mention
  in the notification.
- Net::HTTP delivery with hardcoded 3 second open and read timeouts.
- English and French locales.

## Compatibility

| Component | Version       |
| --------- | ------------- |
| Redmine   | >= 6.1.0      |
| Rails     | 7.2           |
| Ruby      | >= 3.2        |
| Slack     | Incoming webhooks (legacy `attachments` payload) |

## Install

> [!IMPORTANT]
> The plugin directory under `plugins/` must be named `redmine_kalvad_slack`.
> The repository slug on GitHub is `redmine-slack` (with a hyphen) but Redmine
> requires the directory name to match the plugin id passed to
> `Redmine::Plugin.register`, which is `redmine_kalvad_slack` (with
> underscores). The clone, submodule, or symlink commands below all rename to
> the correct path. If you have already cloned to a different name, run
> `git mv plugins/<wrong-name> plugins/redmine_kalvad_slack` from inside your
> Redmine checkout.

### Option 1: clone

```bash
cd <redmine>/plugins
git clone https://github.com/KalvadTech/redmine-slack.git redmine_kalvad_slack
cd ..
bundle install
bundle exec rake redmine:plugins:migrate RAILS_ENV=production NAME=redmine_kalvad_slack
```

### Option 2: submodule

```bash
cd <redmine>
git submodule add https://github.com/KalvadTech/redmine-slack.git plugins/redmine_kalvad_slack
git submodule update --init --recursive
bundle install
bundle exec rake redmine:plugins:migrate RAILS_ENV=production NAME=redmine_kalvad_slack
```

### Option 3: symlink (development)

```bash
ln -s <path-to-this-repo> <redmine>/plugins/redmine_kalvad_slack
cd <redmine>
bundle install
bundle exec rake redmine:plugins:migrate RAILS_ENV=development NAME=redmine_kalvad_slack
```

Restart Redmine.

## Uninstall

```bash
cd <redmine>
bundle exec rake redmine:plugins:migrate NAME=redmine_kalvad_slack VERSION=0 RAILS_ENV=production
rm -rf plugins/redmine_kalvad_slack
```

## Configuration

There is no global configuration. Each project sets its own Slack target.

### Permissions

Grant `Manage Kalvad Slack` to the roles that should be allowed to edit the
per-project tab. Set under `Administration -> Roles and permissions`.

### Per-project tab

`Project -> Settings -> Slack`.

| Field | Notes |
| --- | --- |
| Slack webhook URL | Incoming webhook URL from Slack. Required. |
| Channel | e.g. `#redmine`. Required. Set to a single dash (`-`) to disable notifications without clearing the rest of the config. |
| Posted as | Display name shown in Slack. Defaults to `Redmine`. |
| Icon | `:emoji:` code or HTTPS URL. Optional. |
| Enabled | Master toggle. Off disables all delivery for this project. |
| Per-event toggles | Issue created, updated, closed, wiki created, wiki updated, news. |
| Privacy gates | `Post private issues`, `Post private notes`. Off by default. |
| Display watchers | Adds a watchers field on issue creation. |
| Include description on creation | Adds the issue description as the attachment text. |

A project posts to Slack only if all of these are true: a `KalvadSlackSetting`
row exists, `enabled` is on, the webhook URL is non-blank, and the channel is
non-blank and not `-`.

## @Mentions

The plugin supports two forms of Slack @mentions:

### 1. Inline @username in text

When an issue description or journal note contains `@username` patterns (e.g.
`@john.doe`), they are extracted and appended to the Slack message as
"To: @john.doe". This relies on Slack's `link_names` parameter to resolve
usernames to real mentions.

### 2. Assignee Slack user ID

If a Redmine user has the `Slack Userid` custom field populated with their
Slack member ID (e.g. `U01ABCDEF`), the assignee field in notifications will
use `<@U01ABCDEF>` format, triggering a direct Slack mention/notification.

To set this up:
1. Go to `Administration -> Custom fields -> Users`
2. Ensure a field named **Slack Userid** exists (type: User, format: text)
3. Each user fills in their Slack member ID (found in their Slack profile
   under "More" -> "Copy member ID")

## Events

| Event             | Color  |
| ----------------- | ------ |
| Issue created     | green  |
| Issue updated     | blue   |
| Issue closed      | grey   |
| Wiki page created | purple |
| Wiki page updated | purple |
| News              | yellow |

## Behavior notes

- Delivery is fire-and-forget over `Net::HTTP` with a hardcoded 3 second open
  and read timeout. Failures are logged at `warn` and swallowed: a Slack
  outage will never raise out of a Redmine save.
- No retries. Slack incoming webhooks tolerate roughly one message per second
  per channel; bulk updates will burst.
- No external gem dependencies.
- Translations: English (`en`) and French (`fr`).

## Troubleshooting

- Nothing is posted: check `log/production.log` for lines tagged
  `[redmine_kalvad_slack]`. Confirm the project's `Slack` tab has a webhook
  URL, a channel that is not `-`, and `Enabled` ticked.
- 4xx from Slack: usually a bad webhook URL or a channel the webhook is not
  authorized for.

## Development

```bash
# Lint
gem install rubocop --version '~> 1.71'
rubocop

# Tests (requires a Redmine 6 checkout with this plugin under plugins/)
bundle exec rake redmine:plugins:test NAME=redmine_kalvad_slack
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and PR conventions, and
[AGENTS.md](AGENTS.md) for guidance when working with AI coding assistants.

## Test with Docker

A self-contained Redmine 6 + SQLite + plugin stack ships with the repo. Two
options, depending on whether you want a static image or a live-reload dev
loop.

### docker compose (live-mount, recommended)

```bash
docker compose up
```

This pulls `redmine:6.1`, bind-mounts the repo as the plugin (read-only),
and stores SQLite and uploaded files in named volumes so restarts keep the
data. First boot runs `db:migrate` and `redmine:plugins:migrate`
automatically. Browse http://localhost:3000 and log in as `admin` / `admin`
(Redmine forces a password change on first login).

Restart the container to pick up plugin code changes:

```bash
docker compose restart
```

Wipe the database and files:

```bash
docker compose down -v
```

### Standalone Dockerfile

For a built-in image (no live mount):

```bash
docker build -t redmine-kalvad-slack:test .
docker run --rm -p 3000:3000 redmine-kalvad-slack:test
```

The plugin source is baked into the image at build time. Useful for CI or
one-shot smoke tests, not for iterating on plugin code.

### Smoke test once the container is up

1. Log in as `admin`, change the password.
2. `Administration -> Roles and permissions`. Pick a role (e.g. Manager).
   Tick `Manage Kalvad Slack`. Save.
3. Create or open a project. Open `Settings`. The `Slack` tab appears as
   the last tab.
4. Paste an incoming-webhook URL, set a channel like `#test`, leave the
   defaults, save.
5. Create an issue. Watch the channel. A green attachment lands within a
   couple of seconds.

## Security

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
