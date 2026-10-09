# frozen_string_literal: true

module Api
  # Content Security Policy violation reports from browsers. The policy's
  # report-uri points here (config/initializers/content_security_policy.rb).
  # A browser sends no token, and the path is under /api so the Cloudflare
  # Worker sends it straight to Rails. CspReports logs and counts each report.
  class CspReportsController < BaseController
    CONTENT_TYPES = [ "application/csp-report", "application/reports+json" ].freeze

    # A real report is about 1 KB. The Reporting API can batch a few.
    MAX_BODY_BYTES = 32.kilobytes

    def create
      return render_error("Send application/csp-report or application/reports+json", status: :unsupported_media_type) unless CONTENT_TYPES.include?(request.media_type)
      return render_report_too_large if request.content_length.to_i > MAX_BODY_BYTES

      # A chunked body has no Content-Length, so read at most one byte more
      # than the limit to find out.
      body = request.body.read(MAX_BODY_BYTES + 1).to_s
      return render_report_too_large if body.bytesize > MAX_BODY_BYTES

      CspReports.record(body, content_type: request.media_type)
      head :no_content
    rescue JSON::ParserError
      render_error "The report is not valid JSON", status: :bad_request
    end

    private

    def render_report_too_large
      render_error "The report is larger than #{MAX_BODY_BYTES} bytes", status: :content_too_large
    end
  end
end
