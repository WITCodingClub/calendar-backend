# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preferences::MeetingTimeContext do
  subject(:variables) { described_class.new(meeting_time.reload).variables }

  let(:course)       { create(:course, schedule_type: :lecture) }
  let(:meeting_time) { create(:course_meeting_time, course: course) }
  let(:hall)         { create(:building, name: "FCT Context Hall") }

  def add_room(number, building: hall)
    create(:course_meeting_time_room, meeting_time: meeting_time, room: create(:room, building: building, number: number))
  end

  let!(:minevich)  { create(:faculty, email: "minevichi@wit.edu", first_name: "Igor", last_name: "Minevich") }
  let!(:sanderson) { create(:faculty, email: "sandersone1@wit.edu", first_name: "Elijah", last_name: "Sanderson") }

  # The instructor who was attached first is not always the one teaching the
  # section. Before the join carried Banner's primary flag, the event named
  # whichever row was oldest.
  it "names Banner's primary instructor, not the oldest join row" do
    create(:course_faculty, course: course, faculty: minevich, primary_indicator: false)
    create(:course_faculty, course: course, faculty: sanderson, primary_indicator: true)

    expect(variables).to include(faculty: "Elijah Sanderson", faculty_email: "sandersone1@wit.edu",
                                 all_faculty: "Elijah Sanderson, Igor Minevich")
  end

  it "leaves the instructor blank when the section has none" do
    expect(variables).to include(faculty: "", faculty_email: "")
  end

  it "joins the rooms and names the building" do
    add_room("112")
    add_room("7B")

    expect(variables).to include(building: "FCT Context Hall", room: "112 / 7B", location: "FCT Context Hall - 112 / 7B")
  end

  # Room "0" is the catalog's placeholder (Room#tbd?).
  it "shows TBD for a placeholder room" do
    add_room("0")

    expect(variables).to include(building: "FCT Context Hall", room: "TBD", location: "TBD")
  end

  it "leaves out a placeholder building" do
    add_room("112", building: create(:building, name: "FCT To Be Determined", abbreviation: "FCTBD"))

    expect(variables).to include(building: "", room: "112", location: "112")
  end

  it "leaves the place blank without a room" do
    expect(variables).to include(building: "", room: "", location: "")
  end

  it "shortens Laboratory to Lab" do
    course.update!(schedule_type: :laboratory)

    expect(variables).to include(schedule_type: "Laboratory", schedule_type_short: "Lab")
  end

  describe "#default" do
    it "uses the person's lecture color" do
      config = UserExtensionConfig.new(default_color_lecture: "#123456")

      expect(described_class.new(meeting_time).default(:color_id, config)).to eq("#123456")
    end

    it "uses the meeting's own color without a config" do
      expect(described_class.new(meeting_time).default(:color_id, nil)).to eq(meeting_time.event_color)
    end
  end
end
