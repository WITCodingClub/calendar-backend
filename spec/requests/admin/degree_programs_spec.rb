# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::DegreePrograms", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:program) { create(:degree_program, name: "Computer Science, B.S.", slug: "computer-science-bs") }
  let(:year_2023) { create(:catalog_year, :imported, start_year: 2023) }
  let(:year_2024) { create(:catalog_year, :imported, start_year: 2024) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLive::SyncJob).to receive(:in_progress?).and_return(false)
    sign_in admin
  end

  describe "GET /admin/degree_programs" do
    it "lists programs with their catalog years, and filters by name and kind" do
      create(:requirement_set, degree_program: program, catalog_year: year_2023)
      create(:requirement_set, degree_program: program, catalog_year: year_2024)
      create(:degree_program, :minor, name: "Mathematics Minor")

      get admin_degree_programs_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Computer Science, B.S.", "2023-2024 to 2024-2025", "Mathematics Minor")

      get admin_degree_programs_path(search: "computer")
      expect(response.body).not_to include("Mathematics Minor")

      get admin_degree_programs_path(kind: "minor")
      expect(response.body).to include("Mathematics Minor")
      expect(response.body).not_to include("Computer Science, B.S.")
    end
  end

  describe "GET /admin/degree_programs/:id" do
    let!(:old_set) { create(:requirement_set, degree_program: program, catalog_year: year_2023, name: "Computer Science, B.S. (2023)") }
    let!(:set) { create(:requirement_set, degree_program: program, catalog_year: year_2024) }

    before do
      plan = create(:program_plan, requirement_set: set, name: "Four Year Program", total_credits: 128)
      list = create(:elective_group, requirement_set: set, name: "Computer Science Electives", min_courses: 4)
      create(:program_plan_item, program_plan: plan, year_index: 1, season: "fall", subject_code: "COMP", course_number: 1000)
      create(:program_plan_item, :placeholder, program_plan: plan, year_index: 1, season: "spring", elective_group: list)
      create(:program_plan_item, :choice, program_plan: plan, year_index: 2, season: "fall")
      create(:catalog_year_course, catalog_year: year_2024, subject_code: "COMP", course_number: 1000, title: "COMPUTER SCIENCE I")
      create(:elective_group_course, :requires_approval, elective_group: list, subject_code: "COMP", course_number: 4500)
    end

    it "shows the newest catalog year: its plans semester by semester and its elective lists" do
      get admin_degree_program_path("computer-science-bs")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Four Year Program", "Year 1, Fall", "Year 1, Spring", "Year 2, Fall")
      expect(response.body).to include("COMP 1000", "COMPUTER SCIENCE I", "One of:", "COMP 1099")
      expect(response.body).to include("Computer Science Elective", "From the list \"Computer Science Electives\"")
      expect(response.body).to include("At least 4 courses", "COMP 4500", "School approval")
      expect(response.body).not_to include("Computer Science, B.S. (2023)")
    end

    it "shows another catalog year" do
      get admin_degree_program_path("computer-science-bs", year: 2023)

      expect(response.body).to include("Computer Science, B.S. (2023), 2023-2024", "no plan of study in 2023-2024")
    end

    it "marks a set that needs a review" do
      set.update!(needs_review: true, source: "pdf")

      get admin_degree_program_path("computer-science-bs")

      expect(response.body).to include("needs a review")
    end

    it "shows a program with no requirement set" do
      create(:degree_program, slug: "empty-bs")

      get admin_degree_program_path("empty-bs")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No catalog year has requirements for this program.")
    end
  end
end
