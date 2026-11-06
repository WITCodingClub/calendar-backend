# frozen_string_literal: true

require "rails_helper"

# The admin pages of the degree requirements import (#864) in a real browser:
# the import button with its Turbo confirm, and a program page.
RSpec.describe "Admin degree requirements", type: :system do
  let(:catalog_year) { create(:catalog_year, :imported, start_year: 2024) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLive::SyncJob).to receive(:in_progress?).and_return(false)
    sign_in create(:user, :admin)
  end

  it "queues the import of one catalog year from the button" do
    create(:requirement_set, catalog_year: catalog_year)
    # The server runs in another thread, so the spy checks the call and not
    # the queue adapter, which other specs swap.
    allow(DegreeRequirements::ImportJob).to receive(:perform_later)

    visit admin_catalog_years_path
    within("#catalog-years-table tr", text: "2024-2025") do
      accept_confirm("Import the degree requirements of 2024-2025?") { click_button "Re-import" }
    end

    expect(page).to have_text("Queued the import of 2024-2025.")
    expect(DegreeRequirements::ImportJob).to have_received(:perform_later).with(2024, force: false).once
  end

  it "shows a program's plan semester by semester" do
    program = create(:degree_program, name: "Computer Science, B.S.")
    set = create(:requirement_set, degree_program: program, catalog_year: catalog_year)
    plan = create(:program_plan, requirement_set: set, name: "Four Year Program")
    create(:program_plan_item, program_plan: plan, subject_code: "COMP", course_number: 1000, season: "fall")

    visit admin_catalog_year_path(2024)
    click_link "Computer Science, B.S."

    expect(page).to have_css("h1", text: "Computer Science, B.S.")
    expect(page).to have_text("Year 1, Fall")
    expect(page).to have_text("COMP 1000")
  end
end
