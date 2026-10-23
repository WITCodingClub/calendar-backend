# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::ProgramPageParser do
  def parse(fixture)
    described_class.new(file_fixture("degree_requirements/#{fixture}").read).call
  end

  def codes(items)
    items.map { |item| item.kind == "course" ? "#{item.subject_code}#{item.course_number}" : item.kind }
  end

  context "with a bachelor's page with two plans" do
    subject(:page) { parse("program_bachelor.html") }

    let(:four_year) { page.plans.first }

    it "reads the name, year, school, department, and total credits" do
      expect(page).to have_attributes(name: "Widget Design Bachelor of Science", start_year: 2024,
                                      school_name: "The School of Widgetry", department_name: "Widget Design & Gears",
                                      total_credits: 120)
      expect(page.description).to start_with("Students learn to design widgets that turn.")
      expect(page.digest).to match(/\A\h{64}\z/)
    end

    it "names each plan from the heading above it, not from the overview tab" do
      expect(page.plans.map { |plan| [ plan.name, plan.years, plan.accelerated, plan.total_credits ] }).to eq([
        [ "Four Year Program", 2, false, 120 ], [ "Three Year Program", 3, true, 120 ]
      ])
    end

    it "reads the rows of a plan by year and semester" do
      expect(four_year.items.map { |item| [ item.year_index, item.season ] }.uniq).to eq([
        [ 1, "fall" ], [ 1, "spring" ], [ 2, "summer" ]
      ])
      expect(page.plans.last.items.map(&:season)).to eq(%w[fall fall spring summer])
    end

    it "splits a pair of courses into two rows without credits" do
      pair = four_year.items[1..2]

      expect(codes(pair)).to eq(%w[MATH1776 MATH1777])
      expect(pair.map(&:min_credits)).to eq([ nil, nil ])
    end

    it "reads a placeholder with its footnote mark" do
      english = four_year.items[3]

      expect(english).to have_attributes(kind: "placeholder", label: "English Sequence", footnote: "*", min_credits: 4)
    end

    it "reads two courses joined by or as a choice with a credit range" do
      choice = four_year.items[4]

      expect(choice).to have_attributes(kind: "choice", min_credits: 3, max_credits: 4)
      expect(choice.options).to eq([ { "subject_code" => "WDGT", "course_number" => 1050 },
                                     { "subject_code" => "WDGT", "course_number" => 1099 } ])
    end

    it "turns the indented courses under a select note into the options of that note" do
      select_one = four_year.items[5]

      expect(select_one).to have_attributes(kind: "choice", label: "Select one of the following courses:", min_credits: 4)
      expect(select_one.options.pluck("course_number")).to eq([ 2000, 2100 ])
    end

    it "leaves out an indented note with no credits" do
      expect(four_year.items.map(&:label)).not_to include(a_string_including("will also satisfy"))
    end

    it "keeps the footnote of a placeholder and a course with no credits" do
      elective, science, coop = four_year.items.last(3)

      expect(elective).to have_attributes(label: "Widget Elective", footnote: "1")
      expect(science).to have_attributes(label: "Science Elective", footnote: "2")
      expect(coop).to have_attributes(subject_code: "COOP", course_number: 3000, min_credits: nil)
    end

    it "gives each plan the elective lists printed under it" do
      expect(page.groups.map { |group| [ group.name, group.plan_index, group.min_courses ] }).to eq([
        [ "Widget Electives", 0, 4 ], [ "Widget Electives", 1, 2 ]
      ])
    end

    it "marks the courses after an approval note" do
      courses = page.groups.first.courses

      expect(courses.map(&:course_number)).to eq([ 3000, 3100, 3990 ])
      expect(courses.map(&:requires_approval)).to eq([ false, false, true ])
    end

    it "links a placeholder to the list of its own plan" do
      four_year_elective = four_year.items.find { |item| item.label == "Widget Elective" }
      three_year_elective = page.plans.last.items.find { |item| item.label == "Widget Elective" }

      expect(four_year_elective.group_index).to eq(0)
      expect(three_year_elective.group_index).to eq(1)
      expect(four_year.items.find { |item| item.label == "Science Elective" }.group_index).to be_nil
    end
  end

  context "with a minor page" do
    subject(:page) { parse("program_minor.html") }

    it "has no plan and no department" do
      expect(page.plans).to be_empty
      expect(page.department_name).to be_nil
      expect(page.school_name).to eq("The School of Widgetry")
    end

    it "splits the list at each area and each select note" do
      expect(page.groups.map { |group| [ group.name, group.min_courses, group.min_credits ] }).to eq([
        [ "Required Courses: Select one (1) course from the following courses", 1, nil ],
        [ "Required Courses: and complete the following two courses", 2, nil ],
        [ "Elective Requirement: Select two of the following", 2, nil ]
      ])
    end

    it "keeps an or row as a course of its list, and other notes as notes" do
      expect(page.groups.first.courses.map(&:course_number)).to eq([ 2000, 2050 ])
      expect(page.groups.last.notes).to eq("Any 3000-level WDGT course also counts.")
    end

    it "is a list for the whole program" do
      expect(page.groups.map(&:plan_index)).to all(be_nil)
    end
  end

  describe "list minimums" do
    def group_for(heading)
      html = <<~HTML
        <article id="content"><div id="textcontainer"><h4>#{heading}</h4>
        <table class="sc_courselist"><tr><td class="codecol"><a class="bubblelink code">WDGT3000</a></td></tr></table>
        </div></article>
      HTML
      described_class.new(html).call.groups.first
    end

    {
      "Science Electives, select two (2) courses from the following list:" => [ "Science Electives", 2, nil ],
      "General Electives: Select any two 4 credit courses." => [ "General Electives", 2, nil ],
      "Select 8 credits from the following" => [ "Select 8 credits from the following", nil, 8 ],
      "A total of 16 semester credit hours of technical electives" => [ "A total of 16 semester credit hours of technical electives", nil, 16 ],
      "Technical Electives" => [ "Technical Electives", nil, nil ]
    }.each do |heading, (name, courses, credits)|
      it "reads #{heading.inspect}" do
        expect(group_for(heading)).to have_attributes(name: name, min_courses: courses, min_credits: credits)
      end
    end
  end

  it "reads a page with no catalog year mark as having no year" do
    expect(described_class.new("<html><body><h1>Lost</h1></body></html>").call.start_year).to be_nil
  end
end
