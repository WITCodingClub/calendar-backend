# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::SharedElectives do
  let(:set) { create(:requirement_set) }
  let(:plan) { create(:program_plan, requirement_set: set) }

  def slot(label, **attributes)
    create(:program_plan_item, :placeholder, program_plan: plan, label: label, **attributes)
  end

  describe ".rule_for" do
    {
      "HSS Elective" => "HSS Electives",
      "HSS 02 Elective" => "HSS Electives",
      "HHS Elective" => "HSS Electives",
      "Humanities or Social Science Elective" => "HSS Electives",
      "Humanities Elective" => "Humanities Electives",
      "Social Sciences Elective" => "Social Science Electives",
      "English Sequence" => "English Sequence",
      "English Sequence*" => "English Sequence",
      "Co-op Semester" => "Co-op",
      "FREE Elective" => "Free Electives",
      "General Elective 2" => "Free Electives"
    }.each do |label, name|
      it "gives #{label.inspect} the #{name} list" do
        expect(described_class.rule_for(label).name).to eq(name)
      end
    end

    it "gives a directed HSS elective its one course" do
      rule = described_class.rule_for("HSS 03 Elective (PSYC4552)")

      expect(rule).to have_attributes(name: "HSS Elective (PSYC4552)", courses: [ [ "PSYC", 4552 ] ], subject_codes: [])
    end

    it "names no rule for a program elective or a mixed label" do
      labels = [ "CONM Elective", "Math or Science Elective", "Technical Elective", nil,
                 # A bare "Elective" can mean a program elective, and "HSS 3000" a level.
                 "Elective", "Electives 2", "HSS 3000 Elective",
                 # A directed course only counts when the label is an HSS elective.
                 "Math or HSS Elective (MATH2500)" ]

      expect(labels.map { |label| described_class.rule_for(label) }).to all(be_nil)
    end
  end

  describe ".call" do
    it "links each open slot to one shared list for each rule, after the page's own lists" do
      page_list = create(:elective_group, requirement_set: set, position: 0)
      first = slot("HSS Elective")
      second = slot("HSS Elective 2")
      english = slot("English Sequence")
      free = slot("Free Elective")

      expect(described_class.call(set)).to eq(4)

      hss = first.reload.elective_group
      expect(hss).to have_attributes(name: "HSS Electives", program_plan: nil, position: 1, any_course: false)
      expect(hss.subject_codes).to include("HIST", "PSYC", "LITR")
      expect(second.reload.elective_group).to eq(hss)
      expect(english.reload.elective_group.courses.map { |course| [ course.subject_code, course.course_number ] })
        .to eq(described_class::ENGLISH_SEQUENCE)
      expect(free.reload.elective_group).to have_attributes(any_course: true, subject_codes: [])
      expect(set.elective_groups.reload.map(&:position)).to eq([ page_list.position, 1, 2, 3 ])
    end

    it "leaves a slot the page linked, and a slot no rule names" do
      page_list = create(:elective_group, requirement_set: set, name: "HSS Electives")
      linked = slot("HSS Elective", elective_group: page_list)
      program = slot("CONM Elective")

      expect(described_class.call(set)).to eq(0)
      expect([ linked.reload.elective_group, program.reload.elective_group ]).to eq([ page_list, nil ])
    end

    it "reuses its list on a second run" do
      slot("Co-op Semester")
      described_class.call(set)
      later = slot("Co-op Semester")

      expect { described_class.call(set) }.not_to change(ElectiveGroup, :count)
      expect(later.reload.elective_group.courses.map(&:course_number)).to eq([ 3500, 4500, 5000 ])
    end
  end
end
