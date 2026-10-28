# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::IcsFeed::Holidays do
  let(:course) { create(:course) }
  let!(:meeting_time) do
    create(:course_meeting_time, course: course, day_of_week: :monday,
                                 start_date: Time.zone.local(2026, 9, 14), end_date: Time.zone.local(2026, 12, 14))
  end

  def holiday(date, last = date)
    create(:university_calendar_event, category: "holiday",
                                       start_time: Time.zone.local(date.year, date.month, date.day, 0, 0),
                                       end_time: Time.zone.local(last.year, last.month, last.day, 23, 59))
  end

  # start_date is local midnight. A Date compared with it becomes midnight
  # UTC, which is hours earlier, so the preload dropped a holiday that ends
  # on the first day.
  it "keeps holidays on the first and last days of the meeting time" do
    first = holiday(Date.new(2026, 9, 14))
    last  = holiday(Date.new(2026, 12, 14))
    holiday(Date.new(2026, 9, 7))

    preloaded = described_class.new([ course.reload ])
    allow(UniversityCalendarEvent).to receive(:no_class_spans_between).and_call_original

    expect(preloaded.for(meeting_time).map(&:start_time)).to contain_exactly(first.start_time, last.start_time)
    expect(UniversityCalendarEvent).not_to have_received(:no_class_spans_between)
  end

  it "keeps a break of several days that ends on the first day" do
    break_days = holiday(Date.new(2026, 9, 12), Date.new(2026, 9, 14))

    preloaded = described_class.new([ course.reload ])
    allow(UniversityCalendarEvent).to receive(:no_class_spans_between).and_call_original

    expect(preloaded.for(meeting_time).map(&:start_time)).to eq([ break_days.start_time ])
    expect(preloaded.exdates_for(meeting_time, Time.zone.local(2026, 9, 14, 13, 0)))
      .to eq([ Time.zone.local(2026, 9, 14, 13, 0) ])
    expect(UniversityCalendarEvent).not_to have_received(:no_class_spans_between)
  end
end
