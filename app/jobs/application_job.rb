# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  around_perform :track_job_performance
  before_enqueue :track_job_enqueue
  after_perform :track_job_success
  rescue_from(Exception) do |exception|
    track_job_failure(exception)
    raise
  end

  private

  def track_job_enqueue
    StatsD.increment("job.enqueued", tags: job_tags)
  end

  def track_job_performance
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    yield

    duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
    StatsD.measure("job.duration", duration, tags: job_tags)
  end

  def track_job_success
    StatsD.increment("job.success", tags: job_tags)
  end

  def track_job_failure(exception)
    tags = job_tags + ["exception:#{exception.class.name}"]
    StatsD.increment("job.failure", tags: tags)
    StatsD.increment("job.exception", tags: tags)
  end

  def job_tags
    tags = [
      "job:#{self.class.name}",
      "queue:#{queue_name}"
    ]

    # Add execution attempt count if available
    tags << "attempt:#{executions}" if respond_to?(:executions)

    tags
  end

  # Helper methods for custom metrics in jobs
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
