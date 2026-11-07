# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PathwaySync do
  let(:client) { DegreeRequirements::CatalogSiteClient.new(delay: 0, wayback_delay: 0) }
  let(:accelerated_url) { "https://catalog.wit.edu/programs-az/accelerated-programs/" }
  let(:newest) { create(:catalog_year, start_year: 2026) }

  let!(:widget_bs) { program("widget-design-bs", "Widget Design, B.S.") }
  let!(:widget_ms) { program("widget-design-ms", "Master of Widget Design", :master) }
  let!(:sprocket_ms) { program("sprocket-management-masters", "Sprocket Management Masters Degree", :master) }
  let!(:cog_ms) { program("gear-and-cog-engineering-ms", "Gear and Cog Engineering, M.S.", :master) }

  def program(slug, name, *traits, year: newest)
    create(:degree_program, *traits, slug: slug, name: name).tap do |record|
      create(:requirement_set, degree_program: record, catalog_year: year, name: name)
    end
  end

  def sync = described_class.new(client: client).call

  def steps(slug) = ProgramPathway.find_by!(slug: slug).steps.map(&:degree_program)

  before do
    stub_request(:get, accelerated_url)
      .to_return(status: 200, body: file_fixture("degree_requirements/accelerated_programs.html").read)
    stub_request(:get, DegreeRequirements::DOUBLE_LEOPARD_URL)
      .to_return(status: 200, body: file_fixture("degree_requirements/double_leopard.html").read)
  end

  it "makes a combined pathway of each catalog option with a bachelor's, and skips one with a program not imported yet" do
    result = sync

    expect(ProgramPathway.find_by!(slug: "widget-design-bs-and-widget-design-ms"))
      .to have_attributes(kind: "combined", name: "Widget Design, B.S. and Master of Widget Design 5-Year",
                          max_shared_courses: nil, active: true)
    expect(steps("widget-design-bs-and-widget-design-ms")).to eq([ widget_bs, widget_ms ])
    expect(result.skipped).to eq([ "gear-studies-bs-and-gear-studies-ms" ])
    # The all-master's option is on the Double Leopard page as a dual degree.
    expect(ProgramPathway.exists?(slug: "widget-design-ms-and-sprocket-management-masters")).to be(false)
  end

  it "makes a Double Leopard pathway of the master's programs only, matched by subject in the newest catalog year" do
    program("underwater-basketry-ms", "Underwater Basketry, M.S.", :master, year: create(:catalog_year, start_year: 2020))

    result = sync

    expect(ProgramPathway.find_by!(slug: "double-leopard-widget-design-ms"))
      .to have_attributes(kind: "double_leopard", name: "Master of Widget Design (Double Leopard)", max_shared_courses: 2)
    expect(steps("double-leopard-widget-design-ms")).to eq([ widget_ms ])
    expect(steps("double-leopard-gear-and-cog-engineering-ms")).to eq([ cog_ms ])
    expect(ProgramPathway.find_by!(slug: "double-leopard-widget-design-ms-and-sprocket-management-masters"))
      .to have_attributes(name: "Widget Design & Sprocket Management Dual Degree (Double Leopard)")
    expect(steps("double-leopard-widget-design-ms-and-sprocket-management-masters")).to eq([ widget_ms, sprocket_ms ])
    expect(result.unmatched).to eq([ "Underwater Basketry" ])
  end

  it "keeps the steps when nothing changed, keeps a skipped pathway, and sets a pathway no page lists inactive" do
    sync
    step_ids = ProgramPathwayStep.ids
    skipped = create(:program_pathway, slug: "gear-studies-bs-and-gear-studies-ms")
    old = create(:program_pathway, :double_leopard, slug: "double-leopard-retired-ms")
    planned = create(:student_program, :planned, program_pathway: old)

    result = sync

    expect(ProgramPathwayStep.ids).to match_array(step_ids)
    expect(result.deactivated).to eq(1)
    expect(skipped.reload.active).to be(true)
    expect(old.reload.active).to be(false)
    expect(planned.reload.program_pathway).to eq(old)
  end

  it "changes nothing when a page fails to load or lists nothing" do
    old = create(:program_pathway, slug: "kept")
    stub_request(:get, DegreeRequirements::DOUBLE_LEOPARD_URL).to_return(status: 404)
    expect { sync }.to raise_error(DegreeRequirements::FetchError, /not found/)

    stub_request(:get, DegreeRequirements::DOUBLE_LEOPARD_URL).to_return(status: 200, body: "<h2>Programs</h2>")
    expect { sync }.to raise_error(described_class::EmptySourceError)

    stub_request(:get, accelerated_url).to_return(status: 200, body: "<div id='textcontainer'></div>")
    expect { sync }.to raise_error(described_class::EmptySourceError)
    expect(ProgramPathway.sole).to eq(old)
    expect(old.reload.active).to be(true)
  end

  it "reads the subject of a master's program name" do
    expect([ "Computer Science, M.S.", "Computer Science Master of Science", "Master of Architecture",
             "Architecture Masters Degree", "Architecture, M. Arch.", "Electrical and Computer Engineering" ].map { |name| described_class.subject_key(name) })
      .to eq(%w[computerscience computerscience architecture architecture architecture electricalandcomputerengineering])
  end
end
