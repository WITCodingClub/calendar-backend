# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin catalog review", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:catalog_year) { create(:catalog_year, :imported, :from_pdf, start_year: 2014) }
  let!(:pdf_set) do
    create(:requirement_set, :from_pdf, catalog_year: catalog_year, name: "COMPUTER SCIENCE (BCOS)",
                                        path: "/previous-catalogs/WIT_2014-15_Academic_Catalog_.pdf#page=140")
  end
  let!(:course_alias) { create(:course_code_alias, from_course_number: 128, to_course_number: 1000, note: "Computer Science I") }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLive::SyncJob).to receive(:in_progress?).and_return(false)
    sign_in admin
  end

  it "lists the plans and the aliases to check, with a link to the PDF page" do
    create(:requirement_set, catalog_year: catalog_year, name: "Checked HTML set")
    create(:course_code_alias, :reviewed, from_course_number: 201, to_course_number: 1050)

    get admin_catalog_reviews_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("COMPUTER SCIENCE (BCOS)", "2014-2015",
                                     "https://catalog.wit.edu/previous-catalogs/WIT_2014-15_Academic_Catalog_.pdf#page=140",
                                     "COMP 128", "COMP 1000", "Computer Science I")
    expect(response.body).not_to include("Checked HTML set", "COMP 201")
  end

  it "shows the plan rows of a set" do
    plan = create(:program_plan, requirement_set: pdf_set, name: "Computer Science (BCOS)")
    create(:program_plan_item, program_plan: plan, subject_code: "COMP", course_number: 128, label: "Computer Science I")

    get admin_catalog_review_path(pdf_set)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Computer Science (BCOS)", "COMP128", "Computer Science I", "Mark as checked")
  end

  it "shows the elective list of each slot, and what each list counts" do
    plan = create(:program_plan, requirement_set: pdf_set)
    hss = create(:elective_group, :subjects, requirement_set: pdf_set, subject_codes: %w[HIST PSYC])
    create(:program_plan_item, :placeholder, program_plan: plan, label: "HSS Elective", elective_group: hss)
    create(:program_plan_item, :placeholder, program_plan: plan, label: "CONM Elective")

    get admin_catalog_review_path(pdf_set)

    expect(response.body).to include("Elective lists", "HSS Electives", "Any HIST, PSYC course", "None",
                                     "HSS requirement", "Humanities", "Social Sciences")
  end

  it "marks a set as checked" do
    patch review_admin_catalog_review_path(pdf_set)

    expect(response).to redirect_to(admin_catalog_reviews_path)
    expect(pdf_set.reload).to have_attributes(needs_review: false, reviewed_at: be_present)
  end

  it "marks an alias as checked" do
    patch review_admin_course_code_alias_path(course_alias)

    expect(response).to redirect_to(admin_catalog_reviews_path(anchor: "aliases"))
    expect(course_alias.reload.reviewed_at).to be_present
  end

  it "removes a wrong alias" do
    delete admin_course_code_alias_path(course_alias)

    expect(response).to redirect_to(admin_catalog_reviews_path(anchor: "aliases"))
    expect(CourseCodeAlias.exists?(course_alias.id)).to be(false)
  end
end
