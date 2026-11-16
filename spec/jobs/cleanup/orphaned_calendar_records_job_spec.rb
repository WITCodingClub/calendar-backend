# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cleanup::OrphanedCalendarRecordsJob do
  it "keeps the calendar of a person who must sign in again" do
    credential = create(:oauth_credential, token_expires_at: 1.hour.ago, refresh_token: nil)
    calendar = create(:course_calendar, oauth_credential: credential)

    described_class.perform_now

    expect(CourseCalendar.exists?(calendar.id)).to be(true)
  end
end
