# frozen_string_literal: true

# The school's time zone. config.time_zone in config/application.rb sets it.
# NAME is its IANA name ("America/New_York"), the form that Google Calendar,
# iCalendar and browsers take.
module SchoolTimeZone
  NAME = ActiveSupport::TimeZone[Rails.application.config.time_zone].tzinfo.name

  def self.zone
    ActiveSupport::TimeZone[NAME]
  end
end
