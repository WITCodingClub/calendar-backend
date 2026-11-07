# frozen_string_literal: true

require "rails_helper"

# Issue #867: the My programs page.
RSpec.describe "Dashboard::Programs", :degree_planning, type: :request do
  let(:user) { create(:user, :with_processed_courses) }
  let(:page) { Nokogiri::HTML(response.body) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major_program) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }
  let(:minor_program) { create(:degree_program, :minor, slug: "gear-minor", name: "Gear Minor") }
  let(:major_set) { create(:requirement_set, degree_program: major_program, catalog_year: catalog_year) }
  let!(:four_year) { create(:program_plan, requirement_set: major_set) }
  let!(:three_year) { create(:program_plan, :accelerated, requirement_set: major_set) }
  let!(:minor_set) { create(:requirement_set, degree_program: minor_program, catalog_year: catalog_year, name: "Gear Minor") }
  let!(:major) do
    create(:student_program, user: user, name: "Widget Design", degree_program: major_program, catalog_year: catalog_year,
                             catalog_term_uid: 202610)
  end

  before do
    create(:academic_profile, user: user, class_standing: "Sophomore", admit_term_uid: 202610)
    create(:program_plan_item, program_plan: four_year, year_index: 3, season: "fall", subject_code: "WDGT", course_number: 3000)
    create(:program_plan_item, program_plan: four_year, year_index: 1, season: "spring", subject_code: "GEAR", course_number: 2000)
    group = create(:elective_group, requirement_set: minor_set, name: "Gear Electives", min_courses: 1)
    create(:elective_group_course, elective_group: group, subject_code: "GEAR", course_number: 2000)
    sign_in user
  end

  describe "GET /dashboard/programs" do
    it "says that the page is a help for planning and names Stellic" do
      get dashboard_programs_path

      expect(response).to have_http_status(:ok)
      expect(page.at_css("#planning-help").text).to include("not an official degree audit", "Stellic")
    end

    it "shows each program with its catalog year, start term, assumed plan, and the plan against real terms" do
      get dashboard_programs_path

      card = page.at_css("#program-#{major.public_id}")
      expect(card.text.squish).to include("Widget Design", "Major", "2025-2026", "Fall 2025", "Four Year Program", "Assumed")
      expect(card.at_css("[data-plan-form] input[type=submit]")["value"]).to eq("Confirm plan")
      semesters = card.css("[data-plan-terms] h4").map { |heading| heading.text.squish }
      expect(semesters).to eq([ "Year 1, spring: Spring 2026", "Year 3, fall: Fall 2027" ])
    end

    it "shows the same programs as GET /api/user/programs" do
      get dashboard_programs_path
      shown = page.css("#active-programs article").map { |card| card["id"].delete_prefix("program-") }

      get "/api/user/programs", headers: auth_headers_for(user)
      expect(shown).to eq(response.parsed_body["programs"].pluck("id"))
    end

    it "shows a planned minor with the courses it adds" do
      planned = create(:student_program, :planned, user: user, degree_program: minor_program, catalog_year: catalog_year, role: "minor",
                                                 name: "Gear Minor")

      get dashboard_programs_path

      card = page.at_css("#planned-programs #program-#{planned.public_id}")
      expect(card.text.squish).to include("Gear Minor", "Minor", "2025-2026 catalog")
      expect(card.at_css("[data-courses-added]").text.squish).to include("Gear Electives: pick 1", "To do")
    end

    it "marks a course of a planned program that an active program also needs" do
      gadgets = create(:degree_program, slug: "gadgets-bs", name: "Gadgets, B.S.")
      plan = create(:program_plan, requirement_set: create(:requirement_set, degree_program: gadgets, catalog_year: catalog_year))
      create(:program_plan_item, program_plan: plan, subject_code: "WDGT", course_number: 3000)
      create(:program_plan_item, program_plan: plan, subject_code: "GADG", course_number: 1000)
      planned = create(:student_program, :planned, user: user, degree_program: gadgets, catalog_year: catalog_year)

      get dashboard_programs_path

      rows = page.css("#program-#{planned.public_id} [data-courses-added] li").map { |row| row.text.squish }
      expect(rows).to eq([ "WDGT 3000 (also in your programs) To do", "GADG 1000 To do" ])
      expect(page.at_css("#program-#{planned.public_id}").text).to include("1 new, 1 also in your programs")
    end

    it "lists the ended programs with the newest first" do
      create(:student_program, :ended, user: user, name: "Old Major", ended_at: 2.years.ago)
      create(:student_program, :ended, user: user, name: "Newer Major", ended_at: 1.year.ago)

      get dashboard_programs_path

      expect(page.css("#ended-programs li p.font-medium").map(&:text)).to eq([ "Newer Major", "Old Major" ])
    end

    it "renders many programs without an N+1 query" do
      create(:student_program, :minor, user: user, degree_program: minor_program, catalog_year: catalog_year)
      create_list(:degree_program, 2, :minor).each do |program|
        create(:requirement_set, degree_program: program, catalog_year: catalog_year)
        create(:student_program, :planned, user: user, degree_program: program, catalog_year: catalog_year)
      end
      create_list(:student_program, 2, :ended, user: user)

      get dashboard_programs_path

      expect(response).to have_http_status(:ok)
    end

    it "shows a next step when LeopardWeb sent no programs" do
      major.destroy!

      get dashboard_programs_path

      expect(page.at_css("#active-programs [data-empty-state]").text).to include("process a term")
    end
  end

  describe "PATCH /dashboard/programs/:id/plan" do
    it "confirms the assumed plan" do
      patch plan_dashboard_program_path(major.public_id), params: { plan: "Four Year Program" }

      expect(response).to redirect_to(dashboard_programs_path)
      expect(major.reload.plan_name).to eq("Four Year Program")

      get "/api/user/programs", headers: auth_headers_for(user)
      expect(response.parsed_body["programs"].first).to include("plan" => "Four Year Program", "plan_source" => "student")
    end

    it "picks another plan, which degree progress then uses" do
      patch plan_dashboard_program_path(major.public_id), params: { plan: "three year program" }

      expect(major.reload.plan_name).to eq("Three Year Program")
      expect(AcademicProfiles::DegreeProgress.new(user).call[:programs].first[:plan]).to eq("Three Year Program")
    end

    it "refuses a plan the program does not have" do
      patch plan_dashboard_program_path(major.public_id), params: { plan: "Ten Year Program" }

      expect(flash[:alert]).to include("Pick a plan")
      expect(major.reload.plan_name).to be_nil
    end

    it "refuses an ended program" do
      ended = create(:student_program, :ended, user: user, degree_program: major_program, catalog_year: catalog_year)

      patch plan_dashboard_program_path(ended.public_id), params: { plan: "Four Year Program" }

      expect(flash[:alert]).to include("not authorized")
      expect(ended.reload.plan_name).to be_nil
    end

    it "does not find another student's program" do
      other = create(:student_program, degree_program: major_program, catalog_year: catalog_year)

      patch plan_dashboard_program_path(other.public_id), params: { plan: "Four Year Program" }

      expect(response).to have_http_status(:not_found)
      expect(other.reload.plan_name).to be_nil
    end
  end

  describe "PATCH /dashboard/programs/:id" do
    it "corrects a value through the student path of AcademicProfiles::Sync" do
      patch dashboard_program_path(major.public_id), params: { program: { role: "major", name: "Widget Design",
                                                                           department: "Gadgets", catalog_term: "Fall 2025" } }

      expect(response).to redirect_to(dashboard_programs_path)
      expect(major.reload).to have_attributes(department: "Gadgets", source: "student", status: "active")
    end

    it "shows the Sync error and changes nothing for a bad term" do
      patch dashboard_program_path(major.public_id), params: { program: { name: "Widget Design", catalog_term: "Winter" } }

      expect(response).to redirect_to(edit_dashboard_program_path(major.public_id))
      expect(flash[:alert]).to include("catalog_term")
      expect(major.reload.catalog_term_uid).to eq(202610)
    end

    it "refuses a planned program" do
      planned = create(:student_program, :planned, user: user)

      patch dashboard_program_path(planned.public_id), params: { program: { name: "Changed" } }

      expect(flash[:alert]).to include("not authorized")
      expect(planned.reload.name).not_to eq("Changed")
    end
  end

  describe "GET /dashboard/programs/:id/edit" do
    it "fills the form with the stored values" do
      get edit_dashboard_program_path(major.public_id)

      expect(page.at_css("#program_name")["value"]).to eq("Widget Design")
      expect(page.at_css("#program_catalog_term")["value"]).to eq("Fall 2025")
    end
  end

  describe "the profile" do
    it "fills the form and saves a correction" do
      get edit_dashboard_academic_profile_path
      expect(page.at_css("#academic_profile_admit_term")["value"]).to eq("Fall 2025")

      patch dashboard_academic_profile_path, params: { academic_profile: { class_standing: "Junior", admit_term: "Fall 2025" } }

      expect(response).to redirect_to(dashboard_programs_path)
      expect(user.academic_profile.reload).to have_attributes(class_standing: "Junior", admit_term_uid: 202610)
      expect(major.reload.status).to eq("active")
    end

    it "shows the Sync error for a bad admit term" do
      patch dashboard_academic_profile_path, params: { academic_profile: { admit_term: "soon" } }

      expect(flash[:alert]).to include("admit_term")
    end
  end

  describe "planned programs" do
    it "adds a planned program from the catalog with the same checks as the API" do
      post dashboard_planned_programs_path, params: { program: "gear-minor", catalog_year: "2025-2026" }

      expect(response).to redirect_to(dashboard_programs_path(anchor: "planned-programs"))
      expect(user.student_programs.planned.sole).to have_attributes(role: "minor", degree_program: minor_program)

      post dashboard_planned_programs_path, params: { program: "gear-minor" }
      expect(flash[:alert]).to include("already in your programs")
    end

    it "shows the error for an unknown program" do
      post dashboard_planned_programs_path, params: { program: "basket-weaving-bs" }

      expect(flash[:alert]).to include("No program basket-weaving-bs")
      expect(user.student_programs.planned).to be_empty
    end

    it "removes a planned program and never a LeopardWeb program" do
      planned = create(:student_program, :planned, user: user, degree_program: minor_program, catalog_year: catalog_year)

      delete dashboard_planned_program_path(planned.public_id)
      expect(StudentProgram.exists?(planned.id)).to be(false)

      delete dashboard_planned_program_path(major.public_id)
      expect(flash[:alert]).to eq("Planned program not found.")
      expect(major.reload.status).to eq("active")
    end
  end
end
