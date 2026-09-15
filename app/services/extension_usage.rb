# frozen_string_literal: true

# Counts the anonymous usage events that the browser extension sends. The event
# names and the labels are bounded, so a client that sends junk cannot grow the
# number of Prometheus series without limit. docs/metrics.md lists the events.
module ExtensionUsage
  # Keep in sync with TELEMETRY_EVENTS in the extension (client/src/lib/telemetry.ts).
  EVENTS = %w[
    sign_in_google_succeeded
    sign_in_google_failed
    sign_in_wrong_account
    sign_in_passkey_succeeded
    sign_in_passkey_failed
    passkey_created
    passkey_setup_skipped
    calendar_choice_google
    calendar_choice_other
    google_calendar_connected
    schedule_import_succeeded
    schedule_import_failed
    calendar_link_copied
  ].freeze

  BROWSERS = %w[chrome firefox edge].freeze

  MAX_EVENTS_PER_REQUEST = 50

  # Remembers the extension versions it has seen, up to a limit. A real release
  # adds one version. A client that makes up version strings adds many, and
  # past the limit each of them is counted as "other".
  class VersionLabels
    FORMAT = /\A\d{1,3}(\.\d{1,3}){1,3}\z/

    def initialize(limit:)
      @limit = limit
      @seen  = Set.new
      @lock  = Mutex.new
    end

    def label_for(version)
      version = version.to_s
      return "unknown" unless FORMAT.match?(version)

      @lock.synchronize do
        return version if @seen.include?(version)
        return "other" if @seen.size >= @limit

        @seen << version
        version
      end
    end
  end

  VERSIONS = VersionLabels.new(limit: 50)

  class << self
    # Returns the number of events counted.
    def record(events:, version:, browser:)
      labels = {
        version: VERSIONS.label_for(version),
        browser: BROWSERS.include?(browser) ? browser : "other"
      }

      known = Array(events).first(MAX_EVENTS_PER_REQUEST).select { |event| EVENTS.include?(event) }
      known.each { |event| Yabeda.calendar.extension_events_total.increment(labels.merge(event: event)) }
      known.size
    end
  end
end
