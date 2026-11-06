# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::CourseCodeAliasFinder do
  # One plan of study in the grid of the 2013-2014 to 2015-2016 catalogs,
  # with every row in the fall of the first year.
  def grid(heading, rows)
    lines = [ "                  #{heading}",
              "                  Fall Semester                    Spring Semester",
              "        Course                    Credits   Course                 Credits" ]
    rows.each do |code, title|
      lines << "        #{code.ljust(31)}4"
      lines << "        #{title}"
    end
    lines << " Freshman Year"
    lines << "#{'        TOTAL CREDITS'.ljust(39)}#{rows.size * 4}"
    "#{lines.join("\n")}\n\n\n"
  end

  def table_row(code, title) = "Minor\n                    #{code}         #{title.ljust(40)}4\n"

  let(:old_text) do
    grid("WIDGET DESIGN (BWID)", [ [ "WDGT101", "Widget Basics" ], [ "WDGT102", "Widget Theory" ] ]) +
      grid("GADGET STUDIES (BGAD)", [ [ "WDGT101", "Widget Basics" ] ]) +
      table_row("WDGT130", "Widget Safety")
  end
  let(:new_text) do
    grid("WIDGET DESIGN (BWID)", [ [ "WDGT1000", "Widget Basics" ], [ "WDGT1050", "Widget Theory" ] ]) +
      grid("GADGET STUDIES (BGAD)", [ [ "WDGT1070", "Widget Basics" ] ]) +
      table_row("WDGT1300", "Widget Safety") + table_row("WDGT1310", "Widget Safety")
  end

  def find = described_class.new(texts: { 2014 => old_text, 2015 => new_text }).call

  def pairs
    CourseCodeAlias.order(:from_course_number, :to_course_number)
                   .pluck(:from_subject_code, :from_course_number, :to_course_number, :source)
  end

  it "pairs the codes with the same subject and title in the two catalogs" do
    result = find

    expect(pairs).to include([ "WDGT", 102, 1050, "title_match" ])
    expect(CourseCodeAlias.find_by(from_course_number: 102)).to have_attributes(
      reviewed_at: nil, note: "Same title in the 2014-2015 and 2015-2016 catalogs: widget theory"
    )
    expect(result).to have_attributes(created: 3, catalog: 3, banner: 0, existing: 0, conflicts: 0)
  end

  # "Widget Basics" is two new codes. Each took the old code's place in a
  # plan, so the course was split.
  it "pairs an old code with each new code that took its place in a plan" do
    find

    expect(pairs).to include([ "WDGT", 101, 1000, "title_match" ], [ "WDGT", 101, 1070, "title_match" ])
  end

  it "leaves out a title that two new codes have when no plan tells them apart" do
    find

    expect(pairs.map(&:second)).not_to include(130)
  end

  context "with Banner sections" do
    let(:old_term) { create(:term, uid: 201420, year: 2014, season: :spring) }
    let(:new_term) { create(:term, uid: 201610, year: 2015, season: :fall) }

    def section(term, number, title, subject: "Sprockets (SPRK)")
      create(:course, term: term, subject: subject, course_number: number, title: title)
    end

    it "pairs the codes with the same subject and title in Banner" do
      section(old_term, 101, "Sprocket Basics")
      section(new_term, 1000, "Sprocket Basics")

      expect(find).to have_attributes(banner: 1)
      expect(CourseCodeAlias.find_by(from_subject_code: "SPRK")).to have_attributes(
        from_course_number: 101, to_course_number: 1000, source: "banner",
        note: "Same title in Banner: sprocket basics. SPRK101 in 201420, SPRK1000 in 201610"
      )
    end

    it "leaves out an old code when the catalogs and Banner disagree" do
      section(old_term, 102, "Widget Theory", subject: "Widgets (WDGT)")
      section(new_term, 1060, "Widget Theory", subject: "Widgets (WDGT)")

      expect(find.conflicts).to eq(1)
      expect(pairs.map(&:second)).not_to include(102)
    end

    it "leaves out two old codes that the sources pair with one new code" do
      section(old_term, 105, "Widget Theory Lab", subject: "Widgets (WDGT)")
      section(new_term, 1050, "Widget Theory Lab", subject: "Widgets (WDGT)")

      expect(find.conflicts).to eq(2)
      expect(pairs.map(&:third)).not_to include(1050)
    end

    it "keeps one alias when both sources agree" do
      section(old_term, 102, "Widget Theory", subject: "Widgets (WDGT)")
      section(new_term, 1050, "Widget Theory", subject: "Widgets (WDGT)")

      find

      expect(CourseCodeAlias.where(from_course_number: 102).sole.note).to include("catalogs", "Banner")
    end
  end

  it "does not change a stored alias" do
    create(:course_code_alias, from_subject_code: "WDGT", from_course_number: 102, to_subject_code: "WDGT",
                               to_course_number: 1050, source: "admin")
    create(:course_code_alias, from_subject_code: "WDGT", from_course_number: 101, to_subject_code: "WDGT",
                               to_course_number: 1099, source: "admin")

    result = find

    expect(result).to have_attributes(created: 0, existing: 1, conflicts: 2)
    expect(CourseCodeAlias.where(from_course_number: 102).sole.source).to eq("admin")
  end

  it "does not pair a new code that a stored alias gives to another old code" do
    create(:course_code_alias, from_subject_code: "WDGT", from_course_number: 109, to_subject_code: "WDGT",
                               to_course_number: 1050, source: "admin")

    find

    expect(CourseCodeAlias.where(to_course_number: 1050).pluck(:from_course_number)).to eq([ 109 ])
  end

  it "finds nothing in the catalogs without both texts" do
    expect(described_class.new(texts: { 2014 => old_text }).call.created).to eq(0)
  end
end
