# frozen_string_literal: true

module Feeds
  # Public read-only CSV exports (Catalog::ScheduleReports) for BI tools
  # (Power BI Web connector, Excel) and for browser dashboards, which read them
  # across origins.
  #
  # Inherits ActionController::Base, not ApplicationController: consumers are
  # data tools (Power BI, curl), so the allow_browser check must not run here.
  class ReportsController < ActionController::Base
    before_action :set_public_cache

    def meeting_times
      send_csv Catalog::ScheduleReports.new(term_uid: params[:term_uid]).meeting_times_csv, "meeting_times.csv"
    end

    def sections
      send_csv Catalog::ScheduleReports.new(term_uid: params[:term_uid]).sections_csv, "sections.csv"
    end

    def terms
      send_csv Catalog::ScheduleReports.new.terms_csv, "terms.csv"
    end

    private

    # Public course data, cached for an hour. Any origin may read it, so a
    # browser page (a dashboard in SharePoint, for example) can fetch a report
    # directly. Rack::Cors adds the CORS header only when the request has an
    # Origin, and Cloudflare caches the first response for every origin (#684),
    # so the header is set here on every response.
    def set_public_cache
      expires_in 1.hour, public: true
      response.headers["Access-Control-Allow-Origin"] = "*"
    end

    def send_csv(csv, filename)
      send_data csv, type: "text/csv; charset=utf-8", filename: filename, disposition: "inline"
    end
  end
end
