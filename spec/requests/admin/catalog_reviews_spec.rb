# frozen_string_literal: true

require "rails_helper"

# The review queues of the PDF catalog import (#865).
RSpec.describe "Admin catalog reviews", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:catalog_year) { create(:catalog_year, :from_pdf, start_year: 2014, base_url: "https://catalog.wit.edu/previous-catalogs/x.pdf") }
  let(:program) { create(:degree_program, slug: "widget-design-bs") }
  let!(:requirement_set) do
    create(:requirement_set, :from_pdf, degree_program: program, catalog_year: catalog_year, name: "Widget Design (BWID)",
                                        review_notes: "Year 2 fall: the rows add up to 8 credits, the printed total is 10.")
  end

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLive::SyncJob).to receive(:in_progress?).and_return(false)
    sign_in admin
  end

  describe "requirement sets" do
    it "lists the sets that wait for a review, and not the HTML sets" do
      create(:requirement_set, catalog_year: catalog_year, name: "Gadget Studies (HTML)")

      get admin_requirement_set_reviews_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Widget Design (BWID)", "Waiting (1)", "1 to check")
      expect(response.body).not_to include("Gadget Studies (HTML)")
    end

    it "shows the rows of each plan and the failed checks" do
      plan = create(:program_plan, requirement_set: requirement_set, name: "Plan of Study", years: 4)
      create(:program_plan_item, program_plan: plan, subject_code: "WDGT", course_number: 101)
      create(:program_plan_item, :placeholder, program_plan: plan, label: "Widget Elective")

      get admin_requirement_set_review_path(requirement_set)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("WDGT101", "Widget Elective", "the printed total is 10", "Mark as checked")
    end

    it "marks a set as checked" do
      patch admin_requirement_set_review_path(requirement_set)

      expect(response).to redirect_to(admin_requirement_set_reviews_path)
      expect(requirement_set.reload).to have_attributes(needs_review: false, reviewed_at: be_within(1.minute).of(Time.current))
    end

    it "lists the checked sets" do
      requirement_set.update!(needs_review: false, reviewed_at: Time.current)

      get admin_requirement_set_reviews_path(status: "reviewed")

      expect(response.body).to include("Widget Design (BWID)", "Waiting (0)")
    end

    it "does not show a set from the HTML catalog" do
      html_set = create(:requirement_set, catalog_year: catalog_year)

      get admin_requirement_set_review_path(html_set)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "course code aliases" do
    let!(:course_alias) do
      create(:course_code_alias, from_course_number: 128, to_course_number: 1000, note: "Same title in Banner: computer science i")
    end

    it "lists the aliases that wait for a review" do
      create(:course_code_alias, :reviewed, from_course_number: 201, to_course_number: 1050)

      get admin_course_code_alias_reviews_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("COMP 128", "COMP 1000", "computer science i", "Waiting (1)")
      expect(response.body).not_to include("COMP 201")
    end

    it "marks an alias as checked" do
      patch admin_course_code_alias_review_path(course_alias)

      expect(response).to redirect_to(admin_course_code_alias_reviews_path)
      expect(course_alias.reload.reviewed_at).to be_present
    end

    it "deletes a wrong alias" do
      delete admin_course_code_alias_review_path(course_alias)

      expect(response).to redirect_to(admin_course_code_alias_reviews_path)
      expect(CourseCodeAlias.exists?(course_alias.id)).to be(false)
    end
  end

  it "sends a user who is not an admin away" do
    sign_in create(:user)

    patch admin_requirement_set_review_path(requirement_set)

    expect(requirement_set.reload.needs_review).to be(true)
  end
end
