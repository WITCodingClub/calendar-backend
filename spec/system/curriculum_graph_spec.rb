# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Curriculum graph", type: :system do
  let(:user) { create(:user, :with_processed_courses) }
  let(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }
  let(:plan) { create(:program_plan, requirement_set: create(:requirement_set, degree_program: major, catalog_year: catalog_year)) }
  let(:past_term) { create(:term, year: 2025, season: :fall, start_date: Date.new(2025, 9, 1), end_date: Date.new(2025, 12, 20)) }

  def course(number, title, year, season, needs: nil)
    catalog_course = create(:catalog_course, subject_code: "WDGT", course_number: number, title: title)
    create(:course_prerequisite, catalog_course: catalog_course, required_catalog_course: needs) if needs
    create(:program_plan_item, program_plan: plan, subject_code: "WDGT", course_number: number, label: title,
                               year_index: year, season: season)
    catalog_course
  end

  before do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)
    intro = course(1000, "Intro to Widgets", 1, "fall")
    advanced = course(2000, "Advanced Widgets", 1, "spring", needs: intro)
    course(3000, "Widget Capstone", 2, "fall", needs: advanced)
    create(:enrollment, user: user, course: create(:course, term: past_term, subject: "WDGT", course_number: 1000))
    sign_in user
  end

  it "shows the plan by semester and moves the focus to the course a student selects" do
    visit dashboard_curriculum_path

    expect(page).to have_css("#next-semester h2", text: "Next in your plan: Year 1 Spring")
    expect(page).to have_css("svg [data-node='n1'][data-status='done']")
    expect(page).to have_css("svg path[data-edge='n1-n2']")
    expect(page).to have_css("svg path[data-edge='n2-n3']")

    find("svg a[data-node='n2']").click

    within("#focus") do
      expect(page).to have_css("h2", text: "WDGT 2000: Advanced Widgets")
      expect(page).to have_link("WDGT 1000")
      expect(page).to have_link("WDGT 3000")
    end
    expect(page).to have_css("svg a[data-node='n2'][data-focused='true']")

    within("#focus") { click_link "WDGT 3000" }

    expect(page).to have_css("#focus h2", text: "WDGT 3000: Widget Capstone")
    expect(page).to have_css("svg a[data-node='n3'][data-focused='true']")
    expect(page).to have_css("svg a[data-node='n2'][data-focused='false']")
  end
end
