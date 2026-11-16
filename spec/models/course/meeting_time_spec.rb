# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: course_meeting_times
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  day_of_week           :integer          not null
#  end_date              :datetime         not null
#  end_time              :integer          not null
#  hours_week            :integer
#  meeting_schedule_type :integer          not null
#  meeting_type          :integer          not null
#  start_date            :datetime         not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint           not null
#
# Indexes
#
#  index_course_meeting_times_on_course_id    (course_id)
#  index_course_meeting_times_on_day_of_week  (day_of_week)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#
RSpec.describe Course::MeetingTime, type: :model do
  it { is_expected.to belong_to(:course) }
  it { is_expected.to have_many(:meeting_time_rooms).class_name("Course::MeetingTimeRoom").dependent(:destroy) }
  it { is_expected.to have_many(:rooms).through(:meeting_time_rooms) }
  it { is_expected.to have_many(:calendar_events).dependent(:nullify) }
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

  describe "locations" do
    let(:hall)         { create(:building, name: "FCT Sample Hall", abbreviation: "FSH") }
    let(:tbd_building) { create(:building, name: "FCT To Be Determined") }

    def meeting_time_in(*rooms)
      create(:course_meeting_time).tap do |meeting_time|
        rooms.each { |room| create(:course_meeting_time_room, meeting_time: meeting_time, room: room) }
      end
    end

    it "names the building and every real room" do
      meeting_time = meeting_time_in(create(:room, building: hall, number: "12"), create(:room, building: hall, number: "7B"))

      expect(meeting_time.location_text).to eq("FCT Sample Hall - 012 / 7B")
      expect(meeting_time.building_room).to eq("FSH 012 / 7B")
      expect(meeting_time).not_to be_tbd_location
    end

    it "shows TBD for room 0 in a real building" do
      meeting_time = meeting_time_in(create(:room, building: hall, number: "0"))

      expect(meeting_time.location_text).to eq("TBD")
      expect(meeting_time.building_room).to eq("FSH")
      expect(meeting_time).to be_tbd_location
    end

    it "shows only the room when the building is a placeholder" do
      meeting_time = meeting_time_in(create(:room, building: tbd_building, number: "204"))

      expect(meeting_time.location_text).to eq("204")
      expect(meeting_time.building_room).to be_nil
      expect(meeting_time).to be_tbd_location
    end

    it "has no location and counts as TBD with no room" do
      meeting_time = meeting_time_in

      expect(meeting_time.location_text).to be_nil
      expect(meeting_time.building_room).to be_nil
      expect(meeting_time).to be_tbd_location
    end
  end

  describe "#all_day?" do
    it "is true only for the 12:01pm to 11:59pm placeholder times" do
      expect(build(:course_meeting_time, begin_time: 1201, end_time: 2359)).to be_all_day
      expect(build(:course_meeting_time, begin_time: 1201, end_time: 1300)).not_to be_all_day
    end
  end
end
