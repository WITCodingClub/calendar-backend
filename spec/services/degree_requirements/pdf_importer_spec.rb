# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfImporter do
  let(:catalog_year) { create(:catalog_year, start_year: 2014) }
  let(:text) { file_fixture("degree_requirements/pdf_grid.txt").read }
  let!(:program) { create(:degree_program, name: "Widget Design Bachelor of Science", slug: "widget-design-bs") }

  def import(source = text) = described_class.new(catalog_year, text: source).call

  def set = RequirementSet.find_by!(degree_program: program, catalog_year: catalog_year)

  it "writes each matched plan as a set that needs a review" do
    result = import

    expect(result).to have_attributes(status: :imported, imported: 1, unchanged: 0, kept: 0, unmatched: 0, left_out: 1)
    expect(set).to have_attributes(name: "Widget Design (BWID)", source: "pdf", needs_review: true, reviewed_at: nil,
                                   total_credits: 40, path: nil)
    expect(set.review_notes).to eq("Year 2 fall: the rows add up to 8 credits, the printed total is 10.")
    expect(catalog_year.reload).to have_attributes(status: "imported", source: "pdf",
                                                   base_url: "https://catalog.wit.edu/previous-catalogs/WIT_2014-15_Academic_Catalog_.pdf")
  end

  it "writes the plan and its rows" do
    import

    plan = set.program_plans.sole
    expect(plan).to have_attributes(name: "Plan of Study", years: 2, accelerated: false, total_credits: 40)
    expect(plan.items.count).to eq(11)
    expect(plan.items.first).to have_attributes(year_index: 1, season: "fall", kind: "course", subject_code: "WDGT",
                                                course_number: 101, min_credits: 4, max_credits: 4)
    expect(plan.items.where(kind: "choice").sole.options.pluck("course_number")).to eq([ 150, 160 ])
  end

  it "links the rows to the Banner courses" do
    course = create(:catalog_course, subject_code: "WDGT", course_number: 101)

    import

    expect(set.program_plans.sole.items.first.catalog_course).to eq(course)
  end

  it "keeps the review of a set that did not change" do
    import
    set.update!(needs_review: false, reviewed_at: 1.day.ago)

    expect(import).to have_attributes(imported: 0, unchanged: 1)
    expect(set).to have_attributes(needs_review: false, reviewed_at: be_present)
  end

  it "asks for a review again when the set changed" do
    import
    set.update!(needs_review: false, reviewed_at: 1.day.ago)

    expect(import(text.sub("WDGT101", "WDGT111"))).to have_attributes(imported: 1)
    expect(set).to have_attributes(needs_review: true, reviewed_at: nil)
    expect(set.program_plans.sole.items.first.course_number).to eq(111)
  end

  it "never writes over a set from the HTML catalog" do
    create(:requirement_set, degree_program: program, catalog_year: catalog_year, source: "html")

    expect(import).to have_attributes(imported: 0, kept: 1)
    expect(set.source).to eq("html")
    expect(catalog_year.reload.source).not_to eq("pdf")
  end

  it "counts a plan whose program the HTML catalogs do not have" do
    program.destroy!

    expect(import).to have_attributes(imported: 0, unmatched: 1)
    expect(RequirementSet.count).to eq(0)
  end

  # The import cannot tell which of the two is right.
  it "leaves out a program with two different plans of one name" do
    widget = text[/^ +WIDGET DESIGN \(BWID\)$.*?^ +TOTAL CREDITS +10 .*?$/m]
    second = "#{text}\n\n#{widget.sub('WDGT101', 'WDGT111')}\n\nThe end.\n"

    expect(import(second)).to have_attributes(imported: 0, left_out: 3)
    expect(RequirementSet.count).to eq(0)
  end

  it "raises for a year with no PDF parser" do
    expect { described_class.new(create(:catalog_year, start_year: 2020), text: text).call }
      .to raise_error(DegreeRequirements::Error, /no PDF parser/)
  end
end
