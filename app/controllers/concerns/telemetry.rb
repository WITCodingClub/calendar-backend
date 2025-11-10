# frozen_string_literal: true

module Telemetry
  extend ActiveSupport::Concern

  included do
    around_action :track_controller_request
  end

  private

  def track_controller_request
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    yield

    duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0

    tags = build_request_tags(status: response.status)

    StatsD.measure("controller.request.duration", duration, tags: tags)
    StatsD.increment("controller.request.count", tags: tags)

    if response.status >= 400
      StatsD.increment("controller.request.error", tags: tags)
    end
  rescue => e
    duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
    tags = build_request_tags(status: "exception", exception: e.class.name)

    StatsD.measure("controller.request.duration", duration, tags: tags)
    StatsD.increment("controller.request.exception", tags: tags)

    raise
  end

  def build_request_tags(status:, exception: nil)
    tags = [
      "controller:#{controller_name}",
      "action:#{action_name}",
      "method:#{request.method}",
      "status:#{status}",
      "format:#{request.format.symbol}"
    ]

    # Add status class for easier grouping (2xx, 3xx, 4xx, 5xx)
    if status.is_a?(Integer)
      tags << "status_class:#{status / 100}xx"
    end

    # Add exception class if present
    tags << "exception:#{exception}" if exception

    # Add authenticated status
    tags << "authenticated:#{current_user.present?}"

    # Add user access level if authenticated
    if current_user
      tags << "access_level:#{current_user.access_level}"
    end

    tags
  end

  # Helper method for custom metrics in controllers
  def track_metric(metric_name, value = 1, **tags)
    StatsD.increment(metric_name, value, tags: tags.map { |k, v| "#{k}:#{v}" })
  end

  def measure_metric(metric_name, value, **tags)
    StatsD.measure(metric_name, value, tags: tags.map { |k, v| "#{k}:#{v}" })
  end

  def track_timing(metric_name, **tags, &block)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
    measure_metric(metric_name, duration, **tags)
    result
  end
end
