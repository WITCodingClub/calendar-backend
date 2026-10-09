# frozen_string_literal: true

module Feeds
  # The iCalendar feed at /calendar/:token. Calendar apps poll this URL, so it
  # never changes. CourseCalendars::IcsFeed builds the body.
  class CalendarsController < ApplicationController
    skip_before_action :verify_authenticity_token

    def show
      user = User.find_by!(calendar_token: params[:calendar_token])
      feed = CourseCalendars::IcsFeed.new(user)

      respond_to do |format|
        format.ics do
          body = feed.to_ical

          refresh = CourseCalendars::IcsFeed::REFRESH_INTERVAL
          seconds = ActiveSupport::Duration.parse(refresh).to_i

          response.headers["Cache-Control"]      = "max-age=#{seconds}, must-revalidate"
          response.headers["X-Published-TTL"]    = refresh
          response.headers["Refresh-Interval"]   = seconds.to_s

          # The body has no per-request timestamps (DTSTAMP is the last change
          # of each event), so the same data gives the same ETag. A calendar
          # client that sends If-None-Match gets a 304 with no body.
          render plain: body, content_type: "text/calendar" if stale?(etag: body)
        end
      end
    end
  end
end
