# frozen_string_literal: true

require "rails_helper"

RSpec.describe Course::MeetingTime, type: :model do
  it { is_expected.to belong_to(:course) }
  it { is_expected.to have_many(:meeting_time_rooms).class_name("Course::MeetingTimeRoom").dependent(:destroy) }
  it { is_expected.to have_many(:rooms).through(:meeting_time_rooms) }
  it { is_expected.to have_many(:google_calendar_events).dependent(:nullify) }
  it { is_expected.to have_one(:event_preference).dependent(:destroy) }

  it do
    expect(subject).to define_enum_for(:meeting_schedule_type)
      .with_values(lecture: 1, laboratory: 2)
      .backed_by_column_of_type(:integer)
  end

  it { is_expected.to define_enum_for(:meeting_type).with_values(class_meeting: 1).backed_by_column_of_type(:integer) }

  it do
    expect(subject).to define_enum_for(:day_of_week)
      .with_values(sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6)
      .backed_by_column_of_type(:integer)
  end
end
