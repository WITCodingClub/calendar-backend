# frozen_string_literal: true

module Catalog
  # Asks Banner again about the sections of one schedule, after
  # Courses::Processor answered from the stored catalog. The student gets the
  # answer at once, and a seat count or room change since the nightly sync
  # reaches the calendar a little later.
  class SectionRefreshJob < ApplicationJob
    queue_as :default

    # Banner stopped answering. The sections stay as the nightly sync left
    # them, so try again after each cooldown for a short time, then give up.
    include Catalog::BannerCooldownRetry
    retry_banner_cooldown within: 15.minutes

    def perform(course_ids)
      courses = Course.where(id: course_ids)
                      .includes(:term, meeting_times: [ :meeting_time_rooms, { rooms: :building } ])
                      .to_a
      return if courses.empty?

      section_sync = Catalog::SectionSync.new
      flags = CourseCalendars::SyncMarker.enrollment_flags(courses.map(&:id))
      CourseCalendars::SyncMarker.batch_with_enrollment_flags(flags) do
        courses.each do |course|
          section_sync.call(course, course.term.uid)
        rescue Catalog::BannerThrottle::CooldownError
          raise
        rescue => e
          Rails.error.report(e, handled: true, context: { course_id: course.id, crn: course.crn })
        end
      end
    end
  end
end
