# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalendarTemplateRenderer do
  describe ".validate_template" do
    it "validates templates with allowed variables" do
      expect {
        described_class.validate_template("{{title}}: {{course_code}}")
      }.not_to raise_error
    end

    it "rejects templates with invalid Liquid syntax" do
      expect {
        described_class.validate_template("{{unclosed")
      }.to raise_error(CalendarTemplateRenderer::InvalidTemplateError, /Syntax error/)
    end

    it "rejects templates with disallowed variables" do
      expect {
        described_class.validate_template("{{invalid_var}}")
      }.to raise_error(CalendarTemplateRenderer::InvalidTemplateError, /Disallowed variables/)
    end

    it "allows blank templates" do
      expect {
        described_class.validate_template("")
      }.not_to raise_error
    end

    it "allows templates with conditionals" do
      expect {
        described_class.validate_template("{% if faculty %}{{faculty}}{% endif %}")
      }.not_to raise_error
    end
  end

  describe "#render" do
    let(:renderer) { described_class.new }
    let(:context) do
      {
        title: "Computer Science I",
        course_code: "COMP-101-01",
        subject: "COMP",
        course_number: "101",
        room: "306",
        building: "Wentworth Hall",
        start_time: "9:00 AM",
        end_time: "10:30 AM",
        day: "Monday",
        day_abbr: "Mon"
      }
    end

    it "renders simple variable substitution" do
      template = "{{course_code}}: {{title}}"
      result = renderer.render(template, context)
      expect(result).to eq("COMP-101-01: Computer Science I")
    end

    it "renders multiple variables" do
      template = "{{day_abbr}} {{start_time}}: {{title}} in {{room}}"
      result = renderer.render(template, context)
      expect(result).to eq("Mon 9:00 AM: Computer Science I in 306")
    end

    it "handles conditionals" do
      template = "{{title}}{% if room %} - Room {{room}}{% endif %}"
      result = renderer.render(template, context)
      expect(result).to eq("Computer Science I - Room 306")
    end

    it "handles missing variables gracefully" do
      template = "{{title}} - {{faculty}}"
      result = renderer.render(template, context)
      expect(result).to eq("Computer Science I - ")
    end

    it "filters out disallowed context variables" do
      malicious_context = context.merge(evil_var: "malicious")
      template = "{{title}}"
      result = renderer.render(template, malicious_context)
      expect(result).to eq("Computer Science I")
    end

    it "returns fallback for invalid templates" do
      template = "{{invalid}}"
      result = renderer.render(template, context)
      expect(result).to eq("Computer Science I") # Falls back to title
    end

    it "renders plain text without template variables" do
      template = "Math 101 - Lab Session"
      result = renderer.render(template, context)
      expect(result).to eq("Math 101 - Lab Session")
    end

    it "renders mixed plain text and template variables" do
      template = "{{title}} - My Custom Notes"
      result = renderer.render(template, context)
      expect(result).to eq("Computer Science I - My Custom Notes")
    end

    it "handles blank templates" do
      result = renderer.render("", context)
      expect(result).to eq("")
    end

    it "handles nil templates" do
      result = renderer.render(nil, context)
      expect(result).to eq("")
    end
  end

  describe ".build_context_from_meeting_time" do
    let(:term) { create(:term, year: 2024, season: :spring) }
    let(:course) do
      create(:course,
             title: "Computer Science I",
             subject: "COMP",
             course_number: "101",
             section_number: "01",
             crn: "12345",
             schedule_type: "lecture",
             term: term)
    end
    let(:building) { create(:building, name: "Wentworth Hall") }
    let(:room) { create(:room, number: 306, building: building) }
    let(:meeting_time) do
      create(:meeting_time,
             course: course,
             room: room,
             begin_time: 900,
             end_time: 1030,
             day_of_week: :monday)
    end

    it "builds complete context from meeting time" do
      context = described_class.build_context_from_meeting_time(meeting_time)

      expect(context[:title]).to eq("Computer Science I")
      expect(context[:course_code]).to eq("COMP-101-01")
      expect(context[:subject]).to eq("COMP")
      expect(context[:course_number]).to eq(101)
      expect(context[:section_number]).to eq("01")
      expect(context[:crn]).to eq(12345)
      expect(context[:room]).to eq("306")
      expect(context[:building]).to eq("Wentworth Hall")
      expect(context[:location]).to eq("Wentworth Hall - 306")
      expect(context[:start_time]).to eq("9:00 AM")
      expect(context[:end_time]).to eq("10:30 AM")
      expect(context[:day]).to eq("Monday")
      expect(context[:day_abbr]).to eq("Mon")
      expect(context[:term]).to eq("Spring 2024")
      expect(context[:schedule_type]).to eq("Lecture")
      expect(context[:schedule_type_short]).to eq("Lecture")
    end

    it "formats times correctly with AM/PM" do
      meeting_time.begin_time = 1330  # 1:30 PM
      meeting_time.end_time = 1500    # 3:00 PM
      meeting_time.save!

      context = described_class.build_context_from_meeting_time(meeting_time)

      expect(context[:start_time]).to eq("1:30 PM")
      expect(context[:end_time]).to eq("3:00 PM")
    end

    it "handles midnight correctly" do
      meeting_time.begin_time = 0     # 12:00 AM
      meeting_time.end_time = 100     # 1:00 AM
      meeting_time.save!

      context = described_class.build_context_from_meeting_time(meeting_time)

      expect(context[:start_time]).to eq("12:00 AM")
      expect(context[:end_time]).to eq("1:00 AM")
    end

    it "handles noon correctly" do
      meeting_time.begin_time = 1200  # 12:00 PM
      meeting_time.save!

      context = described_class.build_context_from_meeting_time(meeting_time)

      expect(context[:start_time]).to eq("12:00 PM")
    end

    it "handles room numbers correctly" do
      context = described_class.build_context_from_meeting_time(meeting_time)

      expect(context[:room]).to be_present
      expect(context[:building]).to be_present
    end

    it "formats room numbers with leading zeros" do
      # Test single-digit room number (e.g., room 6 should be "006")
      single_digit_room = create(:room, number: 6, building: building)
      meeting_time.room = single_digit_room
      meeting_time.save!

      context = described_class.build_context_from_meeting_time(meeting_time)

      expect(context[:room]).to eq("006")
      expect(context[:location]).to eq("Wentworth Hall - 006")
    end

    it "handles missing faculty gracefully" do
      context = described_class.build_context_from_meeting_time(meeting_time)

      expect(context[:faculty]).to eq("")
      expect(context[:faculty_email]).to eq("")
      expect(context[:all_faculty]).to eq("")
    end

    it "converts laboratory schedule type to 'Lab' in shorthand" do
      course.schedule_type = "laboratory"
      course.save!

      context = described_class.build_context_from_meeting_time(meeting_time)

      expect(context[:schedule_type]).to eq("Laboratory")
      expect(context[:schedule_type_short]).to eq("Lab")
    end

    context "with faculty" do
      let(:faculty1) { create(:faculty, first_name: "Jane", last_name: "Smith", email: "jsmith@example.edu") }
      let(:faculty2) { create(:faculty, first_name: "John", last_name: "Doe", email: "jdoe@example.edu") }

      before do
        course.faculties << faculty1
        course.faculties << faculty2
      end

      it "includes primary faculty" do
        context = described_class.build_context_from_meeting_time(meeting_time)

        expect(context[:faculty]).to eq("Jane Smith")
      end

      it "includes primary faculty email" do
        context = described_class.build_context_from_meeting_time(meeting_time)

        expect(context[:faculty_email]).to eq("jsmith@example.edu")
      end

      it "includes all faculty" do
        context = described_class.build_context_from_meeting_time(meeting_time)

        expect(context[:all_faculty]).to eq("Jane Smith, John Doe")
      end
    end
  end

  describe ".format_time_with_ampm" do
    it "formats morning times correctly" do
      expect(described_class.format_time_with_ampm(900)).to eq("9:00 AM")
      expect(described_class.format_time_with_ampm(1015)).to eq("10:15 AM")
    end

    it "formats afternoon times correctly" do
      expect(described_class.format_time_with_ampm(1300)).to eq("1:00 PM")
      expect(described_class.format_time_with_ampm(1530)).to eq("3:30 PM")
    end

    it "formats midnight correctly" do
      expect(described_class.format_time_with_ampm(0)).to eq("12:00 AM")
    end

    it "formats noon correctly" do
      expect(described_class.format_time_with_ampm(1200)).to eq("12:00 PM")
    end

    it "handles nil gracefully" do
      expect(described_class.format_time_with_ampm(nil)).to eq("")
    end
  end

  describe ".shorthand_schedule_type" do
    it "converts 'laboratory' to 'Lab'" do
      expect(described_class.shorthand_schedule_type("laboratory")).to eq("Lab")
    end

    it "converts 'Laboratory' to 'Lab'" do
      expect(described_class.shorthand_schedule_type("Laboratory")).to eq("Lab")
    end

    it "keeps 'lecture' as 'Lecture'" do
      expect(described_class.shorthand_schedule_type("lecture")).to eq("Lecture")
    end

    it "keeps 'hybrid' as 'Hybrid'" do
      expect(described_class.shorthand_schedule_type("hybrid")).to eq("Hybrid")
    end

    it "handles nil gracefully" do
      expect(described_class.shorthand_schedule_type(nil)).to eq("")
    end

    it "capitalizes unknown schedule types" do
      expect(described_class.shorthand_schedule_type("seminar")).to eq("Seminar")
    end
  end

  describe ".build_context_from_university_calendar_event" do
    let(:event) do
      create(:university_calendar_event,
             summary: "Spring Break",
             description: "No classes this week",
             location: "Campus",
             category: "holiday",
             organization: "University",
             academic_term: "Spring 2025",
             start_time: Time.zone.local(2025, 3, 10, 0, 0, 0),
             end_time: Time.zone.local(2025, 3, 14, 23, 59, 59),
             all_day: true)
    end

    it "builds context with all expected fields" do
      context = described_class.build_context_from_university_calendar_event(event)

      expect(context[:summary]).to eq("Spring Break")
      expect(context[:title]).to eq("Spring Break") # alias
      expect(context[:description]).to eq("No classes this week")
      expect(context[:location]).to eq("Campus")
      expect(context[:category]).to eq("holiday")
      expect(context[:organization]).to eq("University")
      expect(context[:academic_term]).to eq("Spring 2025")
      expect(context[:term]).to eq("Spring 2025") # alias
      expect(context[:event_type]).to eq("university_calendar")
    end

    it "formats time fields correctly" do
      context = described_class.build_context_from_university_calendar_event(event)

      expect(context[:day]).to eq("Monday")
      expect(context[:day_abbr]).to eq("Mon")
    end

    it "provides empty strings for course-related fields" do
      context = described_class.build_context_from_university_calendar_event(event)

      expect(context[:course_code]).to eq("")
      expect(context[:subject]).to eq("")
      expect(context[:faculty]).to eq("")
      expect(context[:crn]).to eq("")
      expect(context[:is_final_exam]).to be false
    end

    it "handles nil values gracefully" do
      event.update!(description: nil, location: nil, organization: nil)
      context = described_class.build_context_from_university_calendar_event(event)

      expect(context[:description]).to eq("")
      expect(context[:location]).to eq("")
      expect(context[:organization]).to eq("")
    end
  end

  describe "ALLOWED_VARIABLES constant" do
    it "includes all expected variables" do
      expected_vars = %w[
        title course_code subject course_number section_number crn
        room building location
        faculty faculty_email all_faculty
        start_time end_time day day_abbr
        term schedule_type schedule_type_short
        exam_date exam_date_short exam_time_of_day duration
        event_type is_final_exam combined_crns
        summary description category organization academic_term
      ]

      expect(CalendarTemplateRenderer::ALLOWED_VARIABLES).to match_array(expected_vars)
    end
  end
end
