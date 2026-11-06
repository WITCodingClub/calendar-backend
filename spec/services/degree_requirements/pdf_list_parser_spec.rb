# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfListParser do
  subject(:result) { described_class.call(file_fixture("degree_requirements/pdf_list.txt").read) }

  def plan(heading) = result.plans.find { |candidate| candidate.heading == heading }

  it "reads each plan under its program name" do
    expect(result.plans.map(&:heading)).to eq([ "Widget Design (BWID)", "Master of Doohickeys (Two-Year)" ])
  end

  it "reads the rows of each semester" do
    items = plan("Widget Design (BWID)").items
    expect(items.map { |item| [ item.year_index, item.season, item.kind, item.subject_code, item.course_number ] }).to eq(
      [
        [ 1, "fall", "course", "WDGT", 1000 ], [ 1, "fall", "course", "MATH", 1000 ], [ 1, "fall", "placeholder", nil, nil ],
        [ 1, "spring", "course", "WDGT", 1050 ], [ 1, "spring", "choice", nil, nil ], [ 1, "spring", "placeholder", nil, nil ],
        [ 2, "summer", "course", "COOP", 3000 ]
      ]
    )
    expect(items.first.title).to eq("Introduction to Widget Design")
    expect(items[2].label).to eq("English Sequence")
    expect(items[5].label).to eq("HSS Elective")
  end

  it "joins a choice that goes on in the next line" do
    choice = plan("Widget Design (BWID)").items[4]
    expect(choice.options).to eq([ { "subject_code" => "WDGT", "course_number" => 1500 },
                                   { "subject_code" => "WDGT", "course_number" => 1600 } ])
  end

  # The bullet list after the plan names a course, but the plan ended.
  it "does not take rows after the note under the last semester" do
    expect(plan("Widget Design (BWID)").items.map(&:course_number)).not_to include(2500)
  end

  it "reads the credits after each title, and warns when a total does not match" do
    doohickeys = plan("Master of Doohickeys (Two-Year)")
    expect(doohickeys.items.map(&:min_credits)).to eq([ 4, 4 ])
    expect(doohickeys.warnings).to eq([ "Year 1 fall: the rows add up to 8 credits, the printed total is 9." ])
  end

  it "leaves out a plan whose semester has text between its rows" do
    expect(result.rejections).to include(
      have_attributes(heading: "Gadget Studies (BGAD)", reason: start_with("text between the rows of a semester"))
    )
  end

  # A concentration between two semesters: the parser cannot tell which
  # rows belong to which program.
  it "leaves out a plan with a program name between two semesters" do
    expect(result.rejections).to include(
      have_attributes(heading: "Sprocket Studies (BSPR)", reason: "a program name between two semesters")
    )
  end

  it "reads a placeholder in capitals without a known word" do
    text = <<~TEXT
      Gadget Studies (BGAD)
      Freshman Year, Fall Semester (total credits 8)
      GADG1000                 Gadgets I (4 credits)
      EC                       Gadget Concentration (4 credits)
    TEXT

    items = described_class.call(text).plans.first.items
    expect(items.last).to have_attributes(kind: "placeholder", label: "Gadget Concentration", min_credits: 4)
  end

  it "splits two rows printed on one line" do
    text = <<~TEXT
      Gadget Studies (BGAD)
      Freshman Year, Fall Semester (total credits 8)
      ELECTIVE, Gadget Engineering 4cr. ELECTIVE, Engineering 4cr.
    TEXT

    expect(described_class.call(text).plans.first.items.map(&:label)).to eq([ "Gadget Engineering Elective", "Engineering Elective" ])
  end

  it "takes the credits of a row from the next line" do
    text = <<~TEXT
      Gadget Studies (BGAD)
      Freshman Year, Fall Semester (total credits 1)
      GADG1600                 Gadget CAD (1 credit) Or GADG1800 Gadget Scripts
      (1 credit)
    TEXT

    expect(described_class.call(text).plans.first.items.first).to have_attributes(kind: "choice", min_credits: 1)
  end

  it "leaves out a plan whose last semester has a row right after text" do
    text = <<~TEXT
      Gadget Studies (BGAD)
      Freshman Year, Fall Semester (total credits 8)
      • GADG1000, Gadgets I
      Students must see their advisor.
      • GADG1100, Gadgets Lab

      Sprocket Studies (BSPR)
    TEXT

    expect(described_class.call(text).rejections.sole.reason).to start_with("text between the rows of the last semester")
  end

  it "leaves out a plan with a year missing" do
    text = "Gadget Studies (BGAD)\nFreshman Year, Fall Semester\nGADG1000, Gadgets I\n" \
           "Junior Year, Fall Semester\nGADG3000, Gadgets IV\n"

    expect(described_class.call(text).rejections.first.reason).to eq("no semester in year 2")
  end

  it "leaves out a plan that goes on after a long text" do
    text = "Gadget Studies (BGAD)\nFreshman Year, Fall Semester\nGADG1000, Gadgets I\n" \
           "#{"Some text about the program.\n" * 30}Sophomore Year, Fall Semester\nGADG2000, Gadgets III\n"

    expect(described_class.call(text)).to have_attributes(
      plans: [], rejections: include(have_attributes(heading: "Gadget Studies (BGAD)", reason: "the plan goes on after a long text"))
    )
  end

  it "notes that the totals were not checked when the rows have no credits" do
    expect(plan("Widget Design (BWID)").warnings).to eq([ "The rows have no credits, so the printed totals were not checked." ])
  end

  it "reads a code in a title and a lowercase or as one course" do
    text = <<~TEXT
      Gadget Studies (BGAD)
      Freshman Year, Fall Semester
      HIST1100, Humanities or Social Change
      HSS 2000-level Elective
    TEXT

    items = described_class.call(text).plans.sole.items
    expect(items.first).to have_attributes(kind: "course", course_number: 1100, title: "Humanities or Social Change")
    expect(items.last).to have_attributes(kind: "placeholder", label: "2000-level Elective")
  end

  it "leaves out semesters that do not start in the first year" do
    text = "Junior Year, Fall Semester (total credits 4)\nGADG3000, Gadgets IV\n"

    expect(described_class.call(text)).to have_attributes(
      plans: [], rejections: [ have_attributes(reason: "semesters that do not start in the first year") ]
    )
  end
end
