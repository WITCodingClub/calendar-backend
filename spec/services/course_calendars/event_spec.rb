# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::Event do
  let(:zone) { SchoolTimeZone.zone }
  let(:meeting_time) { build_stubbed(:course_meeting_time) }

  def event(**fields)
    described_class.new(source: meeting_time, summary: "Programming", start_time: zone.local(2026, 9, 14, 0, 1),
                        end_time: zone.local(2026, 9, 14, 23, 59), **fields)
  end

  it "ends an all-day event on the day after its last day" do
    expect(event(all_day: true).exclusive_end_date).to eq(Date.new(2026, 9, 15))
  end

  it "names the tracking column of its source" do
    expect(event.source_key).to eq([ :meeting_time_id, meeting_time.id ])
  end

  it "keeps the data hash when nothing changes" do
    expect(event.data_hash).to eq(event.with(changed_at: Time.current).data_hash)
  end

  it "changes the data hash with the description" do
    expect(event.data_hash).not_to eq(event(description: "Prof. Other").data_hash)
  end

  it "keeps the recurrence as row lines" do
    recurrence = CourseCalendars::Recurrence.parse([ "RRULE:FREQ=WEEKLY;BYDAY=MO" ])

    expect(event(recurrence: recurrence).fields[:recurrence]).to eq([ "RRULE:FREQ=WEEKLY;BYDAY=MO" ])
  end

  describe ".read_at" do
    include ActiveSupport::Testing::TimeHelpers

    it "is the latest updated_at of the source and the records it shows" do
      meeting_time = create(:course_meeting_time)
      room = create(:room)
      create(:course_meeting_time_room, meeting_time: meeting_time, room: room)
      later = 1.hour.from_now.change(usec: 0)
      travel_to(later) { room.building.touch }

      expect(described_class.read_at(meeting_time.reload)).to eq(later)
    end
  end
end
