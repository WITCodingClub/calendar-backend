# frozen_string_literal: true

# Prometheus metrics for the Grafana server. docs/metrics.md lists the metrics
# and explains how Prometheus reaches the exporter.
require "prometheus/client/data_stores/direct_file_store"

# Solid Queue runs its workers in processes that Puma forks, so a job metric is
# written in a different process from the one that serves the exporter. The
# file store shares the values between those processes. Specs keep the default
# in-memory store.
unless Rails.env.test?
  metrics_dir = ENV.fetch("PROMETHEUS_DATA_DIR") { Rails.root.join("tmp", "prometheus").to_s }
  FileUtils.mkdir_p(metrics_dir)
  Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: metrics_dir)
end

# Health checks run every few seconds and would drown out the real requests.
Yabeda::Rails.config.ignore_actions = [ "Rails::HealthController#show", "OkComputer::OkComputerController#show" ]

Yabeda::ActiveJob.install!

Yabeda.configure do
  group :calendar

  counter :extension_events_total,
          comment: "Anonymous usage events that the browser extension sends.",
          tags: %i[event version browser]

  gauge :users, comment: "Accounts in the database.", aggregation: :most_recent
  gauge :active_sessions, comment: "Sessions that are not revoked or expired.", aggregation: :most_recent
  gauge :google_calendars, comment: "Google calendars that the app syncs.", aggregation: :most_recent
  gauge :jobs, comment: "Solid Queue jobs, by state.", tags: %i[state], aggregation: :most_recent

  collect { AppMetrics.collect }
end
