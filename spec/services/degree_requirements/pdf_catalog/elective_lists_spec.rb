# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfCatalog::ElectiveLists do
  def programs_of(text) = described_class.call(text, DegreeRequirements::PdfCatalog::ListParser.call(text))

  def slot(program, label) = program.plan.items.find { |item| item.label == label }

  def list_of(program, label)
    index = slot(program, label).group_index
    index && program.groups[index]
  end

  def codes(group) = group.courses.map { |course| "#{course.subject_code}#{course.course_number}" }

  # The shape of a 2016-2018 list catalog: a plan, then notes and lists.
  let(:networking) do
    <<~TEXT
      Computer Networking (BSCN)
      Freshman Year, Fall Semester (total credits 16)
      COMP1100, Introduction to Networks
      NET ELECTIVE, Computer Networking Elective
      SEC ELECTIVE, Advanced Security Elective
      HSS ELECTIVE, See ENGL/HSS note below *

      Networking and Security Electives

      Computer Networking students take a total of five major electives. The Computer Networking Elective
      courses may include, but are not limited to:

      COMP2000                Data Structures
      COMP2350                Algorithms
                              with a long title
      COMP3450                Parallel and Distributed Computing

      176
      The Advanced Security Elective courses may include, but are not limited to:
      COMP3800              Special Topics

      Minor in Computer Networking
      To earn the minor, students complete the courses below.
      Core Courses (12 credits, all three courses required)
      COMP1150                Routing and Switching
    TEXT
  end

  it "links each slot to the list that the text above the list names" do
    program = programs_of(networking).sole

    expect(list_of(program, "Computer Networking Elective"))
      .to have_attributes(name: "Computer Networking Electives", min_courses: nil, plan_index: nil)
    expect(codes(list_of(program, "Computer Networking Elective"))).to eq(%w[COMP2000 COMP2350 COMP3450])
    expect(codes(list_of(program, "Advanced Security Elective"))).to eq(%w[COMP3800])
  end

  it "keeps only the lists that a slot names" do
    program = programs_of(networking).sole

    # The minor's "Core Courses" list is near the plan, but no slot names it.
    expect(program.groups.map(&:name)).to contain_exactly("Computer Networking Electives", "Advanced Security Electives")
  end

  it "leaves a shared slot to SharedElectives" do
    program = programs_of(networking).sole

    expect(slot(program, "HSS Elective").group_index).to be_nil
  end

  it "reads the minimum from the lines above the list" do
    text = <<~TEXT
      Computer Science (BCOS)
      Freshman Year, Fall Semester (total credits 8)
      COMP1000, Computer Science I
      ELECTIVE, Advanced Elective

      Advanced Electives - Select one course from the following list (4 credits)
      COMP3200                Assembly Language
      COMP3350                Software Engineering
    TEXT

    group = list_of(programs_of(text).sole, "Advanced Elective")

    expect(group).to have_attributes(name: "Advanced Electives", min_courses: 1, min_credits: nil)
  end

  it "does not read the credits of every course as a minimum" do
    text = <<~TEXT
      Architecture (BSA)
      Freshman Year, Fall Semester (total credits 8)
      ARCH1000, Design Studio
      ELECTIVE, Architecture Elective

      Architecture Electives
      The following list is indicative of the department's elective course offerings: (all courses are 4 credits
      unless otherwise noted)

      ARCH3800                Design Methods
      ARCH3850                Experimental Structures
    TEXT

    expect(list_of(programs_of(text).sole, "Architecture Elective")).to have_attributes(min_courses: nil, min_credits: nil)
  end

  it "reads a list in two columns with sub-headings, named by the paragraph above them" do
    text = <<~TEXT
      Architecture (BSA)
      Freshman Year, Fall Semester (total credits 8)
      ARCH1000, Design Studio
      ELECTIVE, Architecture Elective

      ARCHITECTURE ELECTIVES

      Architecture Electives are listed by concentration. The following list is indicative of the
      Department’s elective course offerings in recent years:

                                     Urbanism
       ARCH435 Design Methods                         ARCH590 Adaptive Reuse as Urban Design
       ARCH590 Analysis of Contemporary Buildings and   ARCH591 Approaches to Public Space
       Architectural Movements
                                                      Design


                                     Professional Practice
       ARCH627 Fundamentals of Design Finance
    TEXT

    group = list_of(programs_of(text).sole, "Architecture Elective")

    expect(group.name).to eq("Architecture Electives")
    expect(codes(group)).to eq(%w[ARCH435 ARCH590 ARCH591 ARCH627])
  end

  it "joins a second part of a list with the same name" do
    text = <<~TEXT
      Computer Networking (BSCN)
      Freshman Year, Fall Semester (total credits 8)
      COMP1100, Introduction to Networks
      ELECTIVE, Advanced Networking Elective

      The Advanced Networking Elective courses will be selected from the following list:

       COMP402 Storage Area Networks                COMP406 Special Topics

      In addition, BSCN students may use certain BCOS courses as Advanced Networking Elective courses.
      The eligible BCOS courses are:

       COMP438 Assembly Language                    COMP460 Game Programming
    TEXT

    program = programs_of(text).sole

    expect(program.groups.size).to eq(1)
    expect(codes(list_of(program, "Advanced Networking Elective"))).to eq(%w[COMP402 COMP406 COMP438 COMP460])
  end

  it "does not read a sentence that starts with a code as a list" do
    text = <<~TEXT
      Electromechanical Engineering (BELM)
      Freshman Year, Fall Semester (total credits 8)
      ELMC1000, Introduction to Electromechanical Engineering
      ELECTIVE, Engineering Elective

      The three BMED electives below are taken as the two General Electives and Engineering Elective:

      BMED260 Physiology for Engineers I, BMED460 Physiology for Engineers II, and BMED660 Biomedical
      Systems Engineering are taken as the two general electives and one engineering elective.
    TEXT

    expect(slot(programs_of(text).sole, "Engineering Elective").group_index).to be_nil
  end

  it "does not read the rows of a plan that no parser reads as a list" do
    text = <<~TEXT
      Mechanical Engineering (BSME)
      Freshman Year, Fall Semester (total credits 8)
      MECH1000, Engineering Graphics
      ELECTIVE, Technical Elective

      Degree Details
      Elective                Technical Elective (4 credits)
      MATH1005                Math A (3 credits)
      PHYS1005                Physics A (3 credits)
    TEXT

    expect(slot(programs_of(text).sole, "Technical Elective").group_index).to be_nil
  end

  it "does not name a list from a heading over a longer paragraph" do
    text = <<~TEXT
      Computer Networking (BSCN)
      Freshman Year, Fall Semester (total credits 8)
      COMP1100, Introduction to Networks
      SCIENCE, Science Elective

      *** Science Elective

      Computer Networking students are required to take one science elective.

      Minor in Computer Networking
      The minor in Computer Networking provides students with an opportunity to learn how the Internet
      works. To earn the minor, students complete the courses below.
      Core Courses (12 credits, all three courses required)
      COMP1100                Introduction to Networks
      COMP1150                Routing and Switching
    TEXT

    expect(slot(programs_of(text).sole, "Science Elective").group_index).to be_nil
  end

  it "links the list under the plan when two lists with the name are as near" do
    text = <<~TEXT
      Computer Science (BCOS)
      Freshman Year, Fall Semester (total credits 8)
      COMP1000, Computer Science I
      COMP ELECTIVE, Computer Science Elective

      Computer Science Electives:
      COMP3100                System Administration

      Computer Networking (BSCN)
      Freshman Year, Fall Semester (total credits 8)
      COMP1100, Introduction to Networks
      COMP ELECTIVE, Computer Science Elective

      Computer Science Electives:
      COMP4450                Systems Programming
    TEXT

    science, networking = programs_of(text)

    expect(codes(list_of(science, "Computer Science Elective"))).to eq(%w[COMP3100])
    expect(codes(list_of(networking, "Computer Science Elective"))).to eq(%w[COMP4450])
  end

  it "does not link the list of another program across that program's plan" do
    description = Array.new(70) { |i| "Line #{i} of the description of the next program." }.join("\n")
    text = <<~TEXT
      Computer Networking (BSCN)
      Freshman Year, Fall Semester (total credits 8)
      COMP1100, Introduction to Networks
      COMP ELECTIVE, Computer Science Elective

      #{description}

      Computer Science (BCOS)
      Freshman Year, Fall Semester (total credits 8)
      COMP1000, Computer Science I
      COMP ELECTIVE, Computer Science Elective

      Computer Science Electives:
      COMP3100                System Administration
    TEXT

    networking, science = programs_of(text)

    expect(slot(networking, "Computer Science Elective").group_index).to be_nil
    expect(codes(list_of(science, "Computer Science Elective"))).to eq(%w[COMP3100])
  end

  it "links one list to each plan of a run of plans above it" do
    text = <<~TEXT
      Architecture - Urbanism Concentration
      Freshman Year, Fall Semester (total credits 8)
      ARCH1000, Design Studio
      ELECTIVE, Architecture Elective

      Architecture - Emerging Technologies Concentration
      Freshman Year, Fall Semester (total credits 8)
      ARCH1000, Design Studio
      ELECTIVE, Architecture Elective

      Architecture Electives
      ARCH3800                Design Methods
    TEXT

    expect(programs_of(text).map { |program| codes(list_of(program, "Architecture Elective")) }).to eq([ %w[ARCH3800], %w[ARCH3800] ])
  end

  it "does not keep a list with the name of a shared list" do
    text = <<~TEXT
      Computer Science (BCOS)
      Freshman Year, Fall Semester (total credits 8)
      COMP1000, Computer Science I
      ELECTIVE, Humanities Elective (Literature)

      Humanities Electives:
      LITR3000                Literature
    TEXT

    program = programs_of(text).sole

    expect(program.groups).to be_empty
    expect(slot(program, "Humanities Elective (Literature)").group_index).to be_nil
  end

  it "does not join two lists with one name far apart" do
    filler = Array.new(20) { |i| "Line #{i} of a note." }.join("\n")
    text = <<~TEXT
      Computer Science (BCOS)
      Freshman Year, Fall Semester (total credits 8)
      COMP1000, Computer Science I
      ELECTIVE, Technical Elective

      Technical Electives:
      COMP3100                System Administration

      #{filler}

      Minor in Computing
      Technical Electives:
      COMP4450                Systems Programming
    TEXT

    expect(codes(list_of(programs_of(text).sole, "Technical Elective"))).to eq(%w[COMP3100])
  end

  it "gives each line of a list year plan to its program" do
    lines = DegreeRequirements::PdfCatalog::ListParser.call(networking).sole.lines

    expect(lines).to eq(1..5)
  end

  it "returns a program with no lines as it is" do
    program = DegreeRequirements::PdfCatalog::Program.new(title: "Plan", code: nil, page: 1, plan: nil)

    expect(described_class.call("COMP1000  Computer Science I", [ program ])).to eq([ program ])
  end
end
