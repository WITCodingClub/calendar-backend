# frozen_string_literal: true

namespace :catalog do
  # The nightly sync re-ingested meeting times with no schedule type, so lab
  # meetings were saved as lectures. A lab section's meetings are labs, so this
  # needs no Banner request. Run it once after the fix is deployed.
  desc "Mark the meeting times of lab sections as labs"
  task fix_lab_meeting_types: :environment do
    lab_types = Course::ScheduleType::TYPES.select { |_key, type| Catalog::MeetingTimesIngest::LAB_SCHEDULE_CODES.include?(type[:code]) }.keys.map(&:to_s)

    meeting_times = Course::MeetingTime.lecture.where(course_id: Course.where(schedule_type: lab_types).select(:id))
    # Calendar events read the type for their color. The next calendar sync
    # updates them, so the timestamps change too.
    fixed = meeting_times.update_all(meeting_schedule_type: Course::MeetingTime.meeting_schedule_types[:laboratory], updated_at: Time.current)

    puts "Marked #{fixed} meeting times as labs."
  end
end
