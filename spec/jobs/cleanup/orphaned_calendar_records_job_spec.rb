# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cleanup::OrphanedCalendarRecordsJob do
  it "keeps the calendar of a person who must sign in again" do
    credential = create(:oauth_credential, token_expires_at: 1.hour.ago, refresh_token: nil)
    calendar = create(:course_calendar, oauth_credential: credential)

    described_class.perform_now

    expect(CourseCalendar.exists?(calendar.id)).to be(true)
  end

  it "is not on the recurring schedule" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    classes = schedule.values.flat_map { |tasks| Array(tasks&.values) }.filter_map { |task| task["class"] if task.is_a?(Hash) }

    expect(classes).not_to include(described_class.name)
  end
end
