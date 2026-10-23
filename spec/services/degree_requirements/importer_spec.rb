# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::Importer do
  let(:catalog_year) { create(:catalog_year, start_year: 2024) }
  let(:client) { DegreeRequirements::CatalogSiteClient.new(delay: 0, wayback_delay: 0) }
  let(:base) { "https://catalog.wit.edu/previous-catalogs/2024-2025" }
  let(:bachelor_url) { "#{base}/widgetry/widget-design/widget-design-bs/" }
  let(:minor_url) { "#{base}/widgetry/widget-design/widget-design-minor/" }

  def fixture(name) = file_fixture("degree_requirements/#{name}").read

  def plain_page(span = "2024-2025")
    "<html><body><article id=\"content\"><h1 class=\"page-title\">A program</h1></article>" \
      "<footer>Boston, MA #{span}</footer></body></html>"
  end

  def import = described_class.new(catalog_year, client: client).call

  before do
    stub_request(:get, "#{base}/programs-az/").to_return(status: 200, body: fixture("programs_az_tree.html"))
    stub_request(:get, %r{\A#{Regexp.escape(base)}/(widgetry|sprockets)/}).to_return(status: 200, body: plain_page)
    stub_request(:get, bachelor_url).to_return(status: 200, body: fixture("program_bachelor.html"))
    stub_request(:get, minor_url).to_return(status: 200, body: fixture("program_minor.html"))
  end

  it "imports every program of the index once" do
    result = import

    expect(result).to have_attributes(status: :imported, programs: 8, updated: 8, unchanged: 0, skipped: 0)
    expect(catalog_year.reload).to have_attributes(status: "imported", source: "html", base_url: "#{base}/")
    expect(catalog_year.imported_at).to be_present
    expect(DegreeProgram.pluck(:slug)).to contain_exactly(
      "widget-design-bs", "widget-design-bs-gears-concentration", "widget-design-ms", "widget-design-minor",
      "exploratory-wd", "gadget-cert", "sprocket-tech-aas", "sprocket-studies-minor"
    )
  end

  it "stores the requirement set, plans, rows, and elective lists of a program" do
    import

    set = DegreeProgram.find_by!(slug: "widget-design-bs").requirement_set_for(catalog_year)
    expect(set).to have_attributes(name: "Widget Design, B.S.", school_name: "The School of Widgetry",
                                   department_name: "Widget Design & Gears", total_credits: 120, source: "html",
                                   path: "/previous-catalogs/2024-2025/widgetry/widget-design/widget-design-bs/")
    expect(set.program_plans.map { |plan| [ plan.name, plan.years, plan.accelerated ] })
      .to eq([ [ "Four Year Program", 2, false ], [ "Three Year Program", 3, true ] ])
    expect(set.program_plans.first.items.pluck(:kind).tally).to eq("course" => 4, "placeholder" => 3, "choice" => 2)
    expect(set.elective_groups.map { |group| [ group.name, group.program_plan&.position, group.courses.size ] })
      .to eq([ [ "Widget Electives", 0, 3 ], [ "Widget Electives", 1, 2 ] ])
  end

  it "links a placeholder to its elective list, and a course code to the Banner course" do
    course = create(:catalog_course, subject_code: "WDGT", course_number: 1000)

    import

    plan = ProgramPlan.find_by!(name: "Four Year Program")
    elective = plan.items.find_by!(label: "Widget Elective")
    expect(elective.elective_group).to eq(plan.elective_groups.first)
    expect(plan.items.find_by!(course_number: 1000).catalog_course).to eq(course)
    expect(ElectiveGroupCourse.find_by!(course_number: 3990)).to have_attributes(requires_approval: true)
  end

  it "reads the kind and level of each program, and links a concentration to its major" do
    import

    expect(DegreeProgram.find_by!(slug: "widget-design-ms")).to have_attributes(kind: "master", level: "graduate")
    expect(DegreeProgram.find_by!(slug: "widget-design-bs-gears-concentration").parent_program)
      .to eq(DegreeProgram.find_by!(slug: "widget-design-bs"))
  end

  describe "a second import" do
    it "skips a page that did not change" do
      import
      set = RequirementSet.find_by!(name: "Widget Design, B.S.")
      set.update_columns(last_seen_at: 2.days.ago)

      result = described_class.new(catalog_year, client: client).call

      expect(result).to have_attributes(updated: 0, unchanged: 8)
      expect(set.reload.last_seen_at).to be_within(1.minute).of(Time.current)
    end

    it "writes a changed page again and keeps the plan ids" do
      import
      plan_ids = ProgramPlan.order(:position).pluck(:id)
      changed = fixture("program_bachelor.html").gsub("WDGT5500", "WDGT5600")
      stub_request(:get, bachelor_url).to_return(status: 200, body: changed)

      result = described_class.new(catalog_year, client: client).call

      expect(result).to have_attributes(updated: 1, unchanged: 7)
      expect(ProgramPlan.order(:position).pluck(:id)).to eq(plan_ids)
      expect(ProgramPlanItem.where(course_number: 5600).count).to eq(1)
      expect(ProgramPlanItem.where(course_number: 5500)).to be_empty
    end

    it "keeps the name from the newest catalog year" do
      program = create(:degree_program, slug: "widget-design-bs", name: "Widget Engineering, B.S.")
      create(:requirement_set, degree_program: program, catalog_year: create(:catalog_year, start_year: 2026))

      import

      expect(program.reload.name).to eq("Widget Engineering, B.S.")
    end
  end

  it "marks a year that no source has as missing" do
    other = create(:catalog_year, start_year: 2030)
    stub_request(:get, "https://catalog.wit.edu/previous-catalogs/2030-2031/programs-az/").to_return(status: 404)
    stub_request(:get, "https://catalog.wit.edu/programs-az/").to_return(status: 200, body: plain_page("2026-2027"))

    result = described_class.new(other, client: client).call

    expect(result.status).to eq(:missing)
    expect(other.reload.status).to eq("missing")
    expect(RequirementSet.count).to eq(0)
  end

  it "keeps the status of an imported year when no source answers" do
    catalog_year.update!(status: "imported", imported_at: 1.day.ago)
    create(:requirement_set, catalog_year: catalog_year)
    stub_request(:get, "#{base}/programs-az/").to_return(status: 200, body: "<p>Down for maintenance</p>")
    stub_request(:get, "https://catalog.wit.edu/programs-az/").to_return(status: 200, body: plain_page("2026-2027"))

    expect(import.status).to eq(:missing)
    expect(catalog_year.reload.status).to eq("imported")
  end

  describe "a short index" do
    before { catalog_year.update!(status: "imported", imported_at: 1.day.ago) }

    it "stops before writing when the index is much shorter than the last import" do
      create_list(:requirement_set, 20, catalog_year: catalog_year, last_seen_at: 1.day.ago)

      expect { import }.to raise_error(DegreeRequirements::ImportShrankError, /lists 8 programs, the last import had 20/)
      expect(RequirementSet.count).to eq(20)
    end

    it "counts only the programs the last import saw" do
      create_list(:requirement_set, 20, catalog_year: catalog_year, last_seen_at: 1.year.ago)

      expect(import.status).to eq(:imported)
    end

    it "imports anyway with force" do
      create_list(:requirement_set, 20, catalog_year: catalog_year, last_seen_at: 1.day.ago)

      expect(described_class.new(catalog_year, client: client, force: true).call.programs).to eq(8)
    end
  end

  it "writes every page again when the parser version changes" do
    import
    stub_const("DegreeRequirements::ProgramPageParser::VERSION", DegreeRequirements::ProgramPageParser::VERSION + 1)

    expect(described_class.new(catalog_year, client: client).call).to have_attributes(updated: 8, unchanged: 0)
  end

  it "lets only the newest catalog year set the parent of a concentration" do
    concentration = create(:degree_program, slug: "widget-design-bs-gears-concentration", kind: "concentration")
    newer_major = create(:degree_program, slug: "gears-bs")
    concentration.update!(parent_program: newer_major)
    create(:requirement_set, degree_program: concentration, catalog_year: create(:catalog_year, start_year: 2026))

    import

    expect(concentration.reload.parent_program).to eq(newer_major)
  end

  it "skips a page from another catalog year, such as an old Wayback capture" do
    stub_request(:get, minor_url).to_return(status: 200, body: plain_page("2023-2024"))

    result = import

    expect(result).to have_attributes(programs: 7, skipped: 1)
    expect(DegreeProgram.find_by(slug: "widget-design-minor")).to be_nil
  end

  it "skips a missing page" do
    stub_request(:get, minor_url).to_return(status: 404)

    expect(import).to have_attributes(programs: 7, skipped: 1)
  end

  it "reports a page that does not parse, and goes on" do
    allow(Rails.error).to receive(:report)
    allow(DegreeRequirements::ProgramPageParser).to receive(:new).and_wrap_original do |original, html|
      raise ArgumentError, "bad page" if html.include?("Widget Design Minor")

      original.call(html)
    end

    expect(import).to have_attributes(programs: 7, skipped: 1)
    expect(Rails.error).to have_received(:report).with(an_instance_of(ArgumentError), hash_including(handled: true))
  end

  it "stops on a fetch error and keeps the stored data" do
    stub_request(:get, minor_url).to_return(status: 500)

    expect { import }.to raise_error(DegreeRequirements::FetchError)
    expect(catalog_year.reload.status).to eq("pending")
  end
end
