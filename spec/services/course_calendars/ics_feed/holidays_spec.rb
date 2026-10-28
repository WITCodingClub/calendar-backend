# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::IcsFeed::Holidays do
  let(:course) { create(:course) }
  let!(:meeting_time) do
    create(:course_meeting_time, course: course, day_of_week: :monday,
                                 start_date: Time.zone.local(2026, 9, 14), end_date: Time.zone.local(2026, 12, 14))
  end

  def holiday(date)
    create(:university_calendar_event, category: "holiday",
                                       start_time: Time.zone.local(date.year, date.month, date.day, 0, 0),
                                       end_time: Time.zone.local(date.year, date.month, date.day, 23, 59))
  end

  # start_date is local midnight. A Date compared with it becomes midnight
  # UTC, which is hours earlier, so the preload dropped a holiday that ends
  # on the first day.
  it "keeps holidays on the first and last days of the meeting time" do
    first = holiday(Date.new(2026, 9, 14))
    last  = holiday(Date.new(2026, 12, 14))
    holiday(Date.new(2026, 9, 7))

    holidays = described_class.new([ course.reload ]).for(meeting_time)

    expect(holidays.map(&:start_time)).to contain_exactly(first.start_time, last.start_time)
  end
end
