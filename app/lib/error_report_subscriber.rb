# frozen_string_literal: true

# Receives every error that reaches Rails.error: the errors that a rescue
# reports with `Rails.error.report(e, handled: true)`, and the errors that the
# request and job executors report when nothing rescues them.
#
# For each error it adds one to calendar_errors_reported_total and writes one
# JSON log line. The app has no error tracker, so these two are the only record
# of an error that a rescue swallows. config/initializers/error_reporting.rb
# subscribes it.
class ErrorReportSubscriber
  BACKTRACE_LINES = 5
  MESSAGE_LIMIT = 500
  UNKNOWN = "unknown"

  LOG_LEVELS = { error: :error, warning: :warn, info: :info }.freeze

  # Rails.error calls this. It must not raise: a failure here would replace the
  # error that the caller reported.
  def report(error, handled:, severity:, context:, source: nil)
    count(error, handled: handled, severity: severity, source: source)
    log(error, handled: handled, severity: severity, context: context, source: source)
  end

  private

  # The labels stay low-cardinality: a class name, a boolean, one of three
  # severities, and a source name from the code. No message or id goes in a
  # label, because each new value makes a new Prometheus series.
  def count(error, handled:, severity:, source:)
    Yabeda.calendar.errors_reported_total.increment(
      error_class: error.class.name || UNKNOWN,
      handled:     handled.to_s,
      severity:    severity.to_s,
      source:      source.presence || UNKNOWN
    )
  rescue StandardError => e
    Rails.logger.warn("ErrorReportSubscriber could not count #{error.class}: #{e.class}: #{e.message}")
  end

  def log(error, handled:, severity:, context:, source:)
    payload = {
      message:     "error_reported",
      error_class: error.class.name || UNKNOWN,
      error:       error.message.to_s.truncate(MESSAGE_LIMIT),
      handled:     handled,
      severity:    severity,
      source:      source,
      context:     scalar_context(context),
      backtrace:   Rails.backtrace_cleaner.clean(Array(error.backtrace)).first(BACKTRACE_LINES)
    }

    Rails.logger.public_send(LOG_LEVELS.fetch(severity, :error), payload.to_json)
  rescue StandardError => e
    Rails.logger.warn("ErrorReportSubscriber could not log #{error.class}: #{e.class}: #{e.message}")
  end

  # Rails adds the current controller or job object to the context. Keep only
  # plain values, such as the ids that the rescue passed.
  def scalar_context(context)
    (context || {}).select do |_key, value|
      value.nil? || value.is_a?(String) || value.is_a?(Symbol) || value.is_a?(Numeric) || value == true || value == false
    end
  end
end
