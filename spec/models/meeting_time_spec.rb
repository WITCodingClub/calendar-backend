# frozen_string_literal: true

# == Schema Information
#
# Table name: meeting_times
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  day_of_week           :integer
#  end_date              :datetime         not null
#  end_time              :integer          not null
#  hours_week            :integer
#  meeting_schedule_type :integer
#  meeting_type          :integer
#  start_date            :datetime         not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint           not null
#  room_id               :bigint           not null
#
# Indexes
#
#  index_meeting_times_on_course_id    (course_id)
#  index_meeting_times_on_day_of_week  (day_of_week)
#  index_meeting_times_on_room_id      (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (room_id => rooms.id)
#
require "rails_helper"

RSpec.describe MeetingTime do
  describe "calendar sync tracking" do
    let(:term) { create(:term) }
    let(:course) { create(:course, term: term) }
    let(:room) { create(:room) }
    let(:meeting_time) { create(:meeting_time, course: course, room: room) }
    let(:user) { create(:user, calendar_needs_sync: false) }
    let!(:oauth_credential) do
      create(:oauth_credential,
             user: user,
             metadata: { "course_calendar_id" => "cal_123" })
    end

    before do
      create(:enrollment, user: user, course: course, term: term)
      user.update_column(:calendar_needs_sync, false)
    end

    context "when meeting time changes" do
      it "marks enrolled users as needing sync" do
        expect {
          meeting_time.update!(begin_time: 1000)
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end

    context "when day_of_week changes" do
      it "marks enrolled users as needing sync" do
        expect {
          meeting_time.update!(day_of_week: :tuesday)
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end

    context "when meeting_time is destroyed" do
      it "marks enrolled users as needing sync" do
        expect {
          meeting_time.destroy
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end
  end

  describe "#building_room" do
    let(:building) { create(:building, abbreviation: "SCI", name: "Science Building") }

    it "formats single digit room numbers with 3 digits" do
      room = create(:room, building: building, number: 6)
      meeting_time = build(:meeting_time, room: room)
      expect(meeting_time.building_room).to eq("SCI 006")
    end

    it "formats double digit room numbers with 3 digits" do
      room = create(:room, building: building, number: 42)
      meeting_time = build(:meeting_time, room: room)
      expect(meeting_time.building_room).to eq("SCI 042")
    end

    it "formats triple digit room numbers as-is" do
      room = create(:room, building: building, number: 123)
      meeting_time = build(:meeting_time, room: room)
      expect(meeting_time.building_room).to eq("SCI 123")
    end

    it "returns only building abbreviation when room number is 0 (TBD)" do
      room = create(:room, building: building, number: 0)
      meeting_time = build(:meeting_time, room: room)
      expect(meeting_time.building_room).to eq("SCI")
    end

    it "returns nil when building is TBD" do
      tbd_building = create(:building, abbreviation: "TBD", name: "To Be Determined")
      room = create(:room, building: tbd_building, number: 100)
      meeting_time = build(:meeting_time, room: room)
      expect(meeting_time.building_room).to be_nil
    end
  end

  describe "#all_day?" do
    it "returns true when event spans 12:01pm to 11:59pm" do
      meeting_time = build(:meeting_time, begin_time: 1201, end_time: 2359)
      expect(meeting_time.all_day?).to be true
    end

    it "returns false for regular timed events" do
      meeting_time = build(:meeting_time, begin_time: 900, end_time: 1050)
      expect(meeting_time.all_day?).to be false
    end

    it "returns false when only begin_time matches" do
      meeting_time = build(:meeting_time, begin_time: 1201, end_time: 1400)
      expect(meeting_time.all_day?).to be false
    end

    it "returns false when only end_time matches" do
      meeting_time = build(:meeting_time, begin_time: 800, end_time: 2359)
      expect(meeting_time.all_day?).to be false
    end
  end
end
