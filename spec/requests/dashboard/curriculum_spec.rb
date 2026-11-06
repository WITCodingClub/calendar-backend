# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/dashboard/curriculum", type: :request do
  let(:user) { create(:user, :with_processed_courses) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }
  let(:plan) { create(:program_plan, requirement_set: create(:requirement_set, degree_program: major, catalog_year: catalog_year)) }

  before { sign_in user }

  it "says how to add a program when the student has none" do
    get dashboard_curriculum_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No major with a plan of study yet.")
  end

  context "with a linked program" do
    before do
      create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)
      create(:program_plan_item, program_plan: plan, subject_code: "WDGT", course_number: 1000, label: "Intro to Widgets")
      create(:catalog_course, subject_code: "WDGT", course_number: 1000, title: "Intro to Widgets")
    end

    it "draws the plan and links each course to its focus" do
      get dashboard_curriculum_path

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#next-semester h2").text).to eq("Next in your plan: Year 1 Fall")
      expect(page.at_css("svg a[data-node='n1']")["href"]).to eq(dashboard_curriculum_path(focus: "WDGT1000"))
    end

    it "keeps the graph and shows an error for an unknown focus course" do
      get dashboard_curriculum_path(focus: "ZZZZ9999")

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("[role=alert]").text).to include("No course ZZZZ9999")
      expect(page.at_css("svg [data-node='n1']")).to be_present
    end

    it "shows only the error for an unknown program" do
      get dashboard_curriculum_path(program: "basket-weaving-bs")

      expect(response.body).to include("No program basket-weaving-bs")
      expect(response.body).not_to include("<svg width")
    end

    it "says when the program has no plan of study" do
      plan.destroy!

      get dashboard_curriculum_path

      expect(response.body).to include("has no plan of study by semester.")
    end
  end
end
