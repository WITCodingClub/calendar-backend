# frozen_string_literal: true

# Counts and logs every error that reaches Rails.error. See
# ErrorReportSubscriber and docs/metrics.md.
#
# to_prepare runs again after a code reload in development. Remove the old
# subscriber first, so that each error is counted once.
Rails.application.reloader.to_prepare do
  Rails.error.unsubscribe(->(subscriber) { subscriber.class.name == "ErrorReportSubscriber" })
  Rails.error.subscribe(ErrorReportSubscriber.new)
end
