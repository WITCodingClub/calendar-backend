# Metrics

The backend sends its metrics to the Grafana server at `telemetry.hogwarts.dev`. Prometheus on nymphadora reads the metrics from alastor over the tailnet. The public internet cannot read them.

```mermaid
flowchart LR
    ext["Browser extension"] -- "POST /api/extension_events" --> web
    subgraph alastor
        web["Puma: Rails app"] --> store[("tmp/prometheus")]
        jobs["Solid Queue workers"] --> store
        store --> exporter["Exporter :9394<br/>in the Puma process"]
        proxy["Socket proxy :9394<br/>tailscale0 only"] --> exporter
    end
    prom["Prometheus on nymphadora"] -- "tailnet" --> proxy
    grafana["Grafana"] --> prom
```

## How the exporter runs

- `config/puma.rb` starts the exporter when `PROMETHEUS_EXPORTER_PORT` is set. Without that variable, the app sends no metrics and opens no port.
- The exporter is a small web server inside the Puma process, on its own port. It does not go through Rails, Thruster, or Traefik.
- The Puma control app starts with the exporter, on `tmp/pumactl.sock`. The exporter reads the Puma thread counts from it.
- Solid Queue workers run in processes that Puma forks. Every process writes its values to files in `tmp/prometheus` (or `PROMETHEUS_DATA_DIR`), and the exporter adds them up. The container gets a new `tmp` on each restart, so no old values stay.

The host side lives in [jaspermayone/infra](https://github.com/jaspermayone/infra):

| File | What it does |
| --- | --- |
| `modules/wit-calendar/default.nix` | `metricsPort` publishes the exporter on loopback, proxies it to the tailnet, and opens the port on `tailscale0` only. |
| `hosts/nymphadora/configuration.nix` | The `wit-calendar` scrape job. |
| `modules/telemetry/dashboards/wit-calendar.json` | The Grafana dashboard. |
| `tailscale/policy.hujson` | The grant from `tag:app` to `tag:ingress` on TCP 9394. |

## Metrics

| Metric | Type | Labels | Source |
| --- | --- | --- | --- |
| `rails_requests_total` | counter | `controller`, `action`, `status`, `format`, `method` | yabeda-rails |
| `rails_request_duration_seconds` | histogram | same as above | yabeda-rails |
| `rails_view_runtime_seconds`, `rails_db_runtime_seconds` | histogram | same as above | yabeda-rails |
| `puma_busy_threads`, `puma_pool_capacity`, `puma_backlog`, `puma_max_threads` | gauge | `index` | yabeda-puma-plugin |
| `activejob_enqueued_total`, `activejob_executed_total`, `activejob_success_total` | counter | `queue`, `activejob`, `executions` | yabeda-activejob |
| `activejob_failed_total` | counter | also `failure_reason` | yabeda-activejob |
| `activejob_runtime_seconds`, `activejob_latency_seconds` | histogram | `queue`, `activejob`, `executions` | yabeda-activejob |
| `calendar_users` | gauge | | `AppMetrics` |
| `calendar_active_sessions` | gauge | | `AppMetrics` |
| `calendar_google_calendars` | gauge | | `AppMetrics` |
| `calendar_jobs` | gauge | `state`: `ready`, `scheduled`, `claimed`, `blocked`, `failed` | `AppMetrics` |
| `calendar_extension_events_total` | counter | `event`, `version`, `browser` | `ExtensionUsage` |
| `calendar_csp_reports_total` | counter | `directive`: the violated directive, for example `script-src-elem`, or `other` | `CspReports` |
| `calendar_api_legacy_requests_total` | counter | `route`: the old path, for example `GET user/email` | `Api::LegacyRouteCounting` |
| `calendar_errors_reported_total` | counter | `error_class`, `handled`, `severity`, `source` | `ErrorReportSubscriber` |

The request metrics skip the health checks (`/up` and OkComputer). The gauges are counted on each scrape. If one count fails, `AppMetrics` reports the error to `Rails.error` and sets the others, so the scrape still succeeds.

## Reported errors

`ErrorReportSubscriber` receives every error that reaches `Rails.error`:

- An error that a rescue reports with `Rails.error.report(e, handled: true)`. These have `handled="true"`.
- An error that nothing rescues in a request or a job. The Rails executor reports it with `handled="false"`, and the source `application.action_dispatch`, `application.solid_queue` or `application.active_support`.

For each error, the subscriber adds one to `calendar_errors_reported_total` and writes one JSON log line with `"message":"error_reported"`. The log line has the error message, the context ids from the rescue, and the first lines of the backtrace. The counter labels have no message and no id, so the number of series stays small.

To find the details of an error in the counter, search the logs for `error_reported` and the error class.

## Extension events

The extension sends `POST /api/extension_events` with a JSON body:

```json
{ "events": ["schedule_import_succeeded"], "version": "4.0.1", "browser": "chrome" }
```

- The request has no token, and nothing in it identifies a student.
- `ExtensionUsage::EVENTS` lists the event names. The backend ignores other names.
- A version that is not in the `4.0.1` format gets the label `unknown`. After 50 different versions, a new version gets `other`. A browser other than `chrome`, `firefox`, or `edge` gets `other`. These limits stop a client from making an unlimited number of series.
- One request counts 50 events at most.
- Rack::Attack allows 120 requests a minute from one IP address, in the `api/extension-events` throttle. The events do not use the anonymous API budget (`api/ip`), because many students share one campus address and sign-in needs that budget.
- Students can turn the events off in the extension Settings. Firefox sends events only when the student allows the optional `technicalAndInteraction` data permission.

To add an event:

1. Add the name to `ExtensionUsage::EVENTS` here, and deploy.
2. Add the same name to `TELEMETRY_EVENTS` in the extension (`src/lib/telemetry.ts`), and call `track`.

If the extension ships first, the backend ignores the new name until step 1 is deployed.

## Try it locally

```bash
PROMETHEUS_EXPORTER_PORT=9394 bin/dev
curl -s localhost:9394/metrics | grep '^calendar_'
```

## Content Security Policy reports

The Content Security Policy is in report-only mode (`config/initializers/content_security_policy.rb`). Browsers do not block anything. They send each violation to `POST /api/csp_reports`.

- `calendar_csp_reports_total` counts the violations, by directive.
- Each violation also writes one warning to the Rails log:

  ```text
  CSP violation: directive=script-src-elem blocked=https://cdn.example.com/x.js document=dashboard/schedules#show
  ```

  `blocked` is the URL without its query string, or a keyword such as `inline` or `eval`. `document` is the route of the page, not its path, because some paths hold a token.

Turn enforcement on when the reports show no violation from the app's own pages.
