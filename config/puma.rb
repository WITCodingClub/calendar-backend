# config/database.yml reads the same RAILS_MAX_THREADS to size the pools (#677).
threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", 3))
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)

plugin :tmp_restart

plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Prometheus metrics for Grafana (docs/metrics.md). The exporter listens on its
# own port, which the host publishes to the tailnet only. It reads the Puma
# thread stats from the control app, so the control app starts too, on a
# socket in tmp.
if ENV["PROMETHEUS_EXPORTER_PORT"]
  activate_control_app "unix://tmp/pumactl.sock", no_token: true
  plugin :yabeda
  plugin :yabeda_prometheus
end

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
