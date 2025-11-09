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
    let(:room) { create(:room, number: "306", building: building) }
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
      expect(context[:class_name]).to eq("Computer Science I")
      expect(context[:course_code]).to eq("COMP-101-01")
      expect(context[:subject]).to eq("COMP")
      expect(context[:course_number]).to eq(101)
      expect(context[:section_number]).to eq("01")
      expect(context[:crn]).to eq(12345)
      expect(context[:room]).to eq(306)
      expect(context[:building]).to eq("Wentworth Hall")
      expect(context[:location]).to eq("Wentworth Hall - 306")
      expect(context[:start_time]).to eq("9:00 AM")
      expect(context[:end_time]).to eq("10:30 AM")
      expect(context[:day]).to eq("Monday")
      expect(context[:day_abbr]).to eq("Mon")
      expect(context[:term]).to eq("Spring 2024")
      expect(context[:schedule_type]).to eq("lecture")
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

    it "handles missing faculty gracefully" do
      context = described_class.build_context_from_meeting_time(meeting_time)

      expect(context[:faculty]).to eq("")
      expect(context[:faculty_email]).to eq("")
      expect(context[:all_faculty]).to eq("")
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

  describe "ALLOWED_VARIABLES constant" do
    it "includes all expected variables" do
      expected_vars = %w[
        title class_name course_code subject course_number section_number crn
        room building location
        faculty faculty_email all_faculty
        start_time end_time day day_abbr
        term schedule_type
      ]

      expect(CalendarTemplateRenderer::ALLOWED_VARIABLES).to match_array(expected_vars)
    end
  end
end
