# frozen_string_literal: true

# A record that shapes the events in its user's calendars. A change that
# commits starts one forced sync (CourseCalendars.resync), so the API, the
# dashboard, the MCP tools and the admin pages need no sync step of their own.
#
# The model says which saves count with #calendar_changed?. A destroyed
# record always counts.
module ResyncsCalendar
  extend ActiveSupport::Concern

  included do
    after_commit :resync_calendar_after_change
  end

  private

  def calendar_changed?
    previously_new_record?
  end

  def resync_calendar_after_change
    return unless user
    return unless destroyed? || calendar_changed?

    CourseCalendars.resync(user, force: true)
  end
end
