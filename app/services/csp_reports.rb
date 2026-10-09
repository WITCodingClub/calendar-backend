# frozen_string_literal: true

# Reads the Content Security Policy violation reports that browsers send to
# Api::CspReportsController. Each violation gets one log line and one count in
# calendar_csp_reports_total. config/initializers/content_security_policy.rb
# has the policy.
#
# Browsers send two formats:
#
# - application/csp-report (report-uri): one object, {"csp-report": {...}},
#   with kebab-case keys.
# - application/reports+json (the Reporting API): an array of reports. A CSP
#   report has "type": "csp-violation" and camelCase keys in "body".
#
# The log line holds no query string and no fragment, because a URL can carry
# a token. Some paths carry a token too (/calendar/:token, /meet/:token), so
# the line names the page by its route, not by its path.
module CspReports
  # The directives that can appear in a report. Anything else is counted as
  # "other", so a client that sends junk cannot add Prometheus series.
  DIRECTIVES = %w[
    base-uri child-src connect-src default-src font-src form-action
    frame-ancestors frame-src img-src manifest-src media-src object-src
    script-src script-src-attr script-src-elem style-src style-src-attr
    style-src-elem worker-src
  ].freeze

  # Values that browsers send in place of a URL for blocked-uri.
  KEYWORDS = %w[inline eval wasm-eval trusted-types-policy trusted-types-sink data blob self].freeze

  MAX_REPORTS_PER_REQUEST = 20
  MAX_VALUE_LENGTH = 200

  Violation = Data.define(:directive, :blocked, :document)

  class << self
    # Returns the violations it logged and counted. Raises JSON::ParserError for
    # a body that is not JSON.
    def record(body, content_type:)
      violations = parse(body, content_type)
      violations.each do |violation|
        Rails.logger.warn(
          "CSP violation: directive=#{violation.directive} blocked=#{violation.blocked} document=#{violation.document}"
        )
        Yabeda.calendar.csp_reports_total.increment({ directive: directive_label(violation.directive) })
      end
      violations
    end

    def parse(body, content_type)
      data = JSON.parse(body)

      reports =
        if content_type == "application/reports+json"
          Array.wrap(data).select { |report| report.is_a?(Hash) && report["type"] == "csp-violation" }
                          .map { |report| report["body"] }
        else
          [ data.is_a?(Hash) ? data["csp-report"] : nil ]
        end

      reports.grep(Hash).first(MAX_REPORTS_PER_REQUEST).map { |report| violation_from(report) }
    end

    private

    def violation_from(report)
      directive = report["effectiveDirective"] || report["effective-directive"] || report["violated-directive"]
      blocked   = report["blockedURL"] || report["blocked-uri"]
      document  = report["documentURL"] || report["document-uri"]

      Violation.new(
        directive: clean(directive.to_s.split.first),
        blocked:   blocked_label(blocked),
        document:  document_label(document)
      )
    end

    def directive_label(directive)
      DIRECTIVES.include?(directive) ? directive : "other"
    end

    # A URL without its query string and fragment, or a keyword such as
    # "inline" or "eval".
    def blocked_label(value)
      value = value.to_s
      return clean(value) if KEYWORDS.include?(value) || value.empty?

      uri = URI.parse(value)
      return clean(uri.scheme) if uri.host.nil?

      clean("#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}#{uri.path}")
    rescue URI::InvalidURIError
      "invalid"
    end

    # The route of the page (controller#action), not its path, because some
    # paths carry a token. A path with no route gives its first segment only.
    def document_label(value)
      path = URI.parse(value.to_s).path.to_s
      route_label(path) || clean("/#{path.split('/').compact_blank.first}")
    rescue URI::InvalidURIError
      "invalid"
    end

    def route_label(path)
      route = Rails.application.routes.recognize_path(path)
      clean("#{route[:controller]}##{route[:action]}")
    rescue StandardError
      # No route, or a route constraint that needs a request (see
      # Rack::Attack.unknown_path?).
      nil
    end

    # Keeps the log line on one line and short.
    def clean(value)
      value = value.to_s.gsub(/[^[:graph:]]/, "")
      value = "unknown" if value.empty?
      value.first(MAX_VALUE_LENGTH)
    end
  end
end
