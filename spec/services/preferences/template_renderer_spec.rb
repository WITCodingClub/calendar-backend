# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preferences::TemplateRenderer do
  let(:course) { create(:course, start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 10, 20)) }

  let(:meeting_time) do
    Catalog::MeetingTimesIngest.call(
      course: course,
      raw_meeting_times: [
        {
          "startDate"           => "09/08/2026",
          "endDate"             => "10/20/2026",
          "beginTime"           => "1300",
          "endTime"             => "1410",
          "building"            => "BEATT",
          "buildingDescription" => "Beatty Hall",
          "room"                => "420",
          "monday"              => true
        }
      ]
    )
    course.meeting_times.first
  end

  let!(:minevich)  { create(:faculty, email: "minevichi@wit.edu", first_name: "Igor", last_name: "Minevich") }
  let!(:sanderson) { create(:faculty, email: "sandersone1@wit.edu", first_name: "Elijah", last_name: "Sanderson") }

  # The instructor who was attached first is not always the one teaching the
  # section. Before the join carried Banner's primary flag, the event named
  # whichever row was oldest.
  it "names Banner's primary instructor, not the oldest join row" do
    create(:course_faculty, course: course, faculty: minevich, primary_indicator: false)
    create(:course_faculty, course: course, faculty: sanderson, primary_indicator: true)

    context = described_class.build_context_from_meeting_time(meeting_time)

    expect(context[:faculty]).to eq("Elijah Sanderson")
    expect(context[:faculty_email]).to eq("sandersone1@wit.edu")
  end

  it "lists every instructor with the primary one first" do
    create(:course_faculty, course: course, faculty: minevich, primary_indicator: false)
    create(:course_faculty, course: course, faculty: sanderson, primary_indicator: true)

    context = described_class.build_context_from_meeting_time(meeting_time)

    expect(context[:all_faculty]).to eq("Elijah Sanderson, Igor Minevich")
  end

  it "leaves the instructor blank when the section has none" do
    context = described_class.build_context_from_meeting_time(meeting_time)

    expect(context[:faculty]).to eq("")
    expect(context[:faculty_email]).to eq("")
  end

  describe "#render" do
    subject(:renderer) { described_class.new }

    it "parses a template once, however many events use it" do
      allow(Liquid::Template).to receive(:parse).and_call_original

      3.times { renderer.render("{{title}} in {{room}}", { title: "Calculus", room: "420" }) }

      # Once to check the template, once to keep it for rendering.
      expect(Liquid::Template).to have_received(:parse).twice
    end

    it "fills each event's own values into a shared template" do
      template = "{{course_code}}: {{title}}"

      expect(renderer.render(template, { course_code: "MATH-1876-03", title: "Calculus 2A" })).to eq("MATH-1876-03: Calculus 2A")
      expect(renderer.render(template, { course_code: "COMP-2000-01", title: "Data Structures" })).to eq("COMP-2000-01: Data Structures")
    end

    it "keeps variables outside the allowed list out of the output" do
      expect(renderer.render("{{title}}{{secret}}", { title: "Calculus", secret: "hidden" })).to eq("Calculus")
    end

    it "falls back to the title every time a template is not allowed" do
      template = "{% for x in (1..3) %}{{title}}{% endfor %}"

      2.times do
        expect(renderer.render(template, { title: "Calculus 2A" })).to eq("Calculus 2A")
      end
    end

    it "returns an empty string for a blank template" do
      expect(renderer.render("", { title: "Calculus" })).to eq("")
    end

    it "renders if, elsif, else, and unless" do
      template = "{% if schedule_type == 'Laboratory' %}{{title | remove: ' - Lab'}} - {{schedule_type_short}}" \
                 "{% elsif schedule_type == 'Lecture' %}{{title}} (Lec){% else %}{{title}}{% endif %}" \
                 "{% unless room == '' %} in {{room}}{% endunless %}"

      expect(renderer.render(template, { title: "Data Structures - Lab", schedule_type: "Laboratory",
                                         schedule_type_short: "Lab", room: "" })).to eq("Data Structures - Lab")
      expect(renderer.render(template, { title: "Data Structures", schedule_type: "Lecture", room: "420" }))
        .to eq("Data Structures (Lec) in 420")
    end

    it "reports a saved template that fails, once for each renderer" do
      allow(Rails.error).to receive(:report)
      saved = described_class.new(user_id: 15)

      2.times { saved.render("{% for x in (1..3) %}{{title}}{% endfor %}", { title: "Calculus" }) }

      expect(Rails.error).to have_received(:report)
        .with(described_class::InvalidTemplateError, handled: true, context: { user_id: 15 }).once
    end

    it "does not report a failing template without a user, as in a preview" do
      allow(Rails.error).to receive(:report)

      renderer.render("{% for x in (1..3) %}{{title}}{% endfor %}", { title: "Calculus" })

      expect(Rails.error).not_to have_received(:report)
    end
  end

  describe ".validate_template" do
    it "accepts if and unless" do
      expect(described_class.validate_template("{% if room %}{{room}}{% else %}TBA{% endif %}{% unless crn %}x{% endunless %}"))
        .to be(true)
    end

    it "rejects a loop, an assign, and an include" do
      [ "{% for x in (1..3) %}{% endfor %}", "{% assign a = title %}", "{% include 'x' %}" ].each do |template|
        expect { described_class.validate_template(template) }
          .to raise_error(described_class::InvalidTemplateError, /Disallowed tags/)
      end
    end

    it "rejects a variable outside the allowed list in a condition" do
      expect { described_class.validate_template("{% if secret == 'x' %}{{title}}{% endif %}") }
        .to raise_error(described_class::InvalidTemplateError, /Disallowed variables: secret/)
    end

    it "rejects a variable outside the allowed list in the body of a condition" do
      expect { described_class.validate_template("{% if title %}{{secret}}{% endif %}") }
        .to raise_error(described_class::InvalidTemplateError, /Disallowed variables: secret/)
    end

    it "rejects a loop inside a condition" do
      expect { described_class.validate_template("{% if title %}{% for x in (1..3) %}{% endfor %}{% endif %}") }
        .to raise_error(described_class::InvalidTemplateError, /Disallowed tags: for/)
    end
  end
end
