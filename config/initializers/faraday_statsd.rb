# frozen_string_literal: true
require "statsd-instrument"

class FaradayStatsd < Faraday::Middleware
  def call(env)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    @app.call(env).on_complete do |resp_env|
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0

      # Base tags
      tags = [
        "method:#{env.method}",
        "host:#{env.url.host}",
        "status:#{resp_env.status}",
        "status_class:#{resp_env.status / 100}xx" # Add status class for easier grouping
      ]

      # Add path if you want (be careful with cardinality)
      # tags << "path:#{env.url.path}" if include_path?

      StatsD.measure("http.client.request.duration", elapsed, tags: tags)
      StatsD.increment("http.client.request.count", tags: tags)

      # Track errors specifically
      if resp_env.status >= 400
        StatsD.increment("http.client.request.error", tags: tags)
      end
    end
  rescue => e
    # Handle exceptions that occur before response
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
    StatsD.measure("http.client.request.duration", elapsed,
                   tags: %W[method:#{env.method} host:#{env.url.host} status:exception])
    StatsD.increment("http.client.request.exception",
                     tags: %W[method:#{env.method} host:#{env.url.host} exception:#{e.class.name}])
    raise
  end
end

# Global registration (optional)
Faraday::Middleware.register_middleware statsd: FaradayStatsd

# Then use it like:
conn = Faraday.new do |f|
  f.use :statsd # If registered
  # or
  f.use FaradayStatsd # Direct usage
  f.adapter Faraday.default_adapter
end