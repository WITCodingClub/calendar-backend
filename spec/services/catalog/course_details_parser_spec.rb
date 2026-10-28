# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::CourseDetailsParser do
  def fixture(name) = file_fixture("leopard_web/#{name}.html").read

  def course(code, number, grade = "TR")
    { "type" => "course", "subject_code" => code, "course_number" => number, "level" => "Undergraduate", "min_grade" => grade }
  end

  def test(score, name = "WIT English Placement Exam")
    { "type" => "test", "name" => name, "score" => score }
  end

  describe ".prerequisites" do
    it "groups by parentheses: (COMP 1050 or COMP 1071) and MATH 2300" do
      expect(described_class.prerequisites(fixture("prerequisites_and_or_groups"))).to eq(
        "type" => "and",
        "operands" => [
          { "type" => "or", "operands" => [ course("COMP", 1050), course("COMP", 1071) ] },
          course("MATH", 2300)
        ]
      )
    end

    it "reads a course or a placement test" do
      expect(described_class.prerequisites(fixture("prerequisites_course_or_test"))).to eq(
        "type" => "or", "operands" => [ course("MATH", 1000), test("1500", "WIT Math Assessment") ]
      )
    end

    it "keeps an or group after an and" do
      expect(described_class.prerequisites(fixture("prerequisites_and_then_or"))).to eq(
        "type" => "and",
        "operands" => [ course("ELEC", 2250), { "type" => "or", "operands" => [ course("MATH", 2500), course("MATH", 2600) ] } ]
      )
    end

    it "nests tests and courses in parenthesized groups" do
      tree = described_class.prerequisites(fixture("prerequisites_tests_nested"))

      expect(tree["type"]).to eq("or")
      expect(tree["operands"].first).to eq(test("1100"))
      expect(tree["operands"].second).to eq("type" => "and", "operands" => [ test("0900"), course("ENGL", 900) ])
      expect(tree["operands"].third["operands"]).to include(course("ENGL", 800, "C"))
    end

    it "returns nil when Banner has none" do
      expect(described_class.prerequisites(fixture("prerequisites_none"))).to be_nil
      expect(described_class.prerequisites("")).to be_nil
    end

    it "binds and tighter than or when there are no parentheses" do
      rows = [ [ "", "", "", "", "Computer Science (COMP)", "1000", "Undergraduate", "D", "" ],
               [ "Or", "", "", "", "Computer Science (COMP)", "1100", "Undergraduate", "D", "" ],
               [ "And", "", "", "", "Mathematics (MATH)", "2300", "Undergraduate", "D", "" ] ]
      html = "<table class=\"basePreqTable\"><tbody>" +
             rows.map { |cells| "<tr>#{cells.map { |c| "<td>#{c}</td>" }.join}</tr>" }.join + "</tbody></table>"

      expect(described_class.prerequisites(html)).to eq(
        "type" => "or",
        "operands" => [ course("COMP", 1000, "D"), { "type" => "and", "operands" => [ course("COMP", 1100, "D"), course("MATH", 2300, "D") ] } ]
      )
    end
  end

  describe ".description" do
    it "drops the prerequisite sentence and reads the credits and terms tail" do
      result = described_class.description(fixture("course_description"))

      expect(result[:description]).to start_with("This course is an introduction to the analysis")
      expect(result[:description]).to end_with("Recursion, sorting and searching are also discussed.")
      expect(result[:description]).not_to include("Prerequisite", "credits")
      expect(result).to include(credit_hours: 4, typically_offered: %w[fall spring])
    end

    {
      "(4 credits) spring, summer"       => [ 4, %w[spring summer] ],
      "(3 credit) fall"                  => [ 3, %w[fall] ],
      "(4 credits) Fall, Spring, Summer" => [ 4, %w[fall spring summer] ],
      "(2 credits)"                      => [ 2, [] ]
    }.each do |tail, (credits, terms)|
      it "reads the tail #{tail.inspect}" do
        result = described_class.description("<section>About the course. #{tail}</section>")

        expect(result).to eq(description: "About the course.", credit_hours: credits, typically_offered: terms)
      end
    end

    it "keeps a description with no tail" do
      expect(described_class.description("<section>Just text.</section>"))
        .to eq(description: "Just text.", credit_hours: nil, typically_offered: [])
    end

    it "is nil for an empty page" do
      expect(described_class.description("<section> </section>")[:description]).to be_nil
    end
  end

  describe ".corequisites" do
    it "lists each course" do
      expect(described_class.corequisites(fixture("corequisites"))).to eq([ { "subject_code" => "PHYS", "course_number" => 1250 } ])
    end

    it "is empty when Banner has none" do
      expect(described_class.corequisites(fixture("corequisites_none"))).to eq([])
    end
  end

  describe ".restrictions" do
    it "groups the values under each heading" do
      groups = described_class.restrictions(fixture("restrictions"))

      expect(groups.first).to eq("heading" => "Cannot be enrolled in one of the following Departments",
                                 "values"  => [ "Workforce Development (WFD)" ])
      expect(groups.second["heading"]).to eq("Cannot be enrolled in one of the following Programs")
      expect(groups.second["values"]).to include("Project Management (BPM)(BS-BPM)")
    end

    it "is empty without restrictions" do
      expect(described_class.restrictions("<section>No restriction information available.</section>")).to eq([])
    end
  end

  describe ".catalog" do
    it "reads the college, division, department, levels, and grading modes without their codes" do
      expect(described_class.catalog(fixture("catalog_details"))).to eq(
        college:       "The School of Comp & Data Sci",
        division:      "COF Eligible Cross Reg",
        department:    "Computer Science & Networking",
        levels:        [ "Undergraduate" ],
        grading_modes: [ "Standard Letter", "Pass/Fail", "Not Graded" ]
      )
    end

    it "gives nil and empty lists for a page with no values" do
      expect(described_class.catalog("")).to eq(college: nil, division: nil, department: nil, levels: [], grading_modes: [])
    end
  end

  describe ".mutual_exclusions" do
    it "reads each excluded course" do
      expect(described_class.mutual_exclusions(fixture("mutual_exclusions"))).to eq(
        [ { "subject_code" => "ARCH", "course_number" => 7250, "level" => "Graduate", "min_grade" => "TR" } ]
      )
    end

    it "is empty without mutual exclusions" do
      expect(described_class.mutual_exclusions(fixture("mutual_exclusions_none"))).to eq([])
    end
  end

  describe ".fees" do
    it "reads each fee with its amount in cents" do
      expect(described_class.fees(fixture("fees"))).to eq(
        [
          { "level" => "Undergraduate", "description" => "Follett Access", "amount_cents" => 9499 },
          { "level" => "Continuing Education", "description" => "Tuition - Workforce Training", "amount_cents" => 200_000 }
        ]
      )
    end

    it "is empty without fees" do
      expect(described_class.fees(fixture("fees_none"))).to eq([])
    end

    it "skips a row whose amount is not a number" do
      html = "<table><tbody><tr><td>Undergraduate</td><td>Lab fee</td><td>TBA</td></tr></tbody></table>"

      expect(described_class.fees(html)).to eq([])
    end
  end

  describe ".learning_objectives" do
    it "keeps one line for each line Banner shows" do
      expect(described_class.learning_objectives(fixture("syllabus"))).to eq(
        "Course Learning Outcomes\n" \
        "1. Explain how binary codes represent data & instructions.\n" \
        "2. Write a simple machine-language program.\n" \
        "3. Use basic command-line utilities to finish a task."
      )
    end

    it "is nil without a syllabus" do
      expect(described_class.learning_objectives(fixture("syllabus_none"))).to be_nil
    end
  end

  it "reads the subject code from a Banner subject" do
    expect(described_class.subject_code("Computer Science (COMP)")).to eq("COMP")
    expect(described_class.subject_code("Computer Science")).to be_nil
  end
end
