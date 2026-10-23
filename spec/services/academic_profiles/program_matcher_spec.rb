# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::ProgramMatcher do
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let!(:cs_bachelor) { create(:degree_program, name: "Computer Science, B.S.", slug: "computer-science-bs") }
  let!(:cs_master) do
    create(:degree_program, :master, name: "Computer Science, M.S.", slug: "computer-science-ms")
  end
  let!(:networking_minor) do
    create(:degree_program, :minor, name: "Computer Networking Minor", slug: "computer-networking-minor")
  end

  def match(**attributes)
    program = create(:student_program, catalog_term_uid: 202610, **attributes)
    described_class.new([ program ]).call
    program.reload
  end

  it "links a major by subject and degree, and the catalog year of its catalog term" do
    program = match(name: "Computer Science", degree: "Bachelor of Science")

    expect(program).to have_attributes(degree_program: cs_bachelor, catalog_year: catalog_year, matched?: true)
  end

  it "uses the degree to pick between a bachelor and a master" do
    expect(match(name: "Computer Science", degree: "Master of Science").degree_program).to eq(cs_master)
  end

  it "uses the degree to pick an associate degree" do
    associate = create(:degree_program, name: "Sprocket Technology, A.A.S.", slug: "sprocket-tech-aas", kind: "associate")

    expect(match(name: "Sprocket Technology", degree: "Associate in Applied Science").degree_program).to eq(associate)
  end

  it "links a minor by role" do
    expect(match(role: "minor", name: "Computer Networking", degree: nil).degree_program).to eq(networking_minor)
  end

  it "leaves the link null when more than one program fits" do
    program = match(name: "Computer Science", degree: nil)

    expect(program).to have_attributes(degree_program: nil, matched?: false)
  end

  it "leaves both links null when the catalog has neither" do
    program = match(name: "Underwater Basket Weaving", catalog_term_uid: 201420)

    expect(program).to have_attributes(degree_program: nil, catalog_year: nil, matched?: nil)
  end

  it "links programs saved before an import with relink_active" do
    program = create(:student_program, name: "Data Science", degree: "Bachelor of Science", catalog_term_uid: 202610)
    data_science = create(:degree_program, name: "Data Science, B.S.", slug: "data-science-bs")

    described_class.relink_active

    expect(program.reload.degree_program).to eq(data_science)
  end
end
