# frozen_string_literal: true

require "rails_helper"

# Issue #867: the My programs page in a browser.
RSpec.describe "My programs", :degree_planning, type: :system do
  let(:user) { create(:user, :with_processed_courses) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major_program) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }
  let(:major_set) { create(:requirement_set, degree_program: major_program, catalog_year: catalog_year) }
  let!(:four_year) { create(:program_plan, requirement_set: major_set) }
  let!(:major) do
    create(:student_program, user: user, name: "Widget Design", degree_program: major_program, catalog_year: catalog_year,
                             catalog_term_uid: 202610)
  end

  before do
    create(:program_plan, :accelerated, requirement_set: major_set)
    create(:program_plan_item, program_plan: four_year, year_index: 3, season: "fall", subject_code: "WDGT", course_number: 3000)
    minor = create(:degree_program, :minor, slug: "gear-minor", name: "Gear Minor")
    group = create(:elective_group, requirement_set: create(:requirement_set, degree_program: minor, catalog_year: catalog_year),
                                    name: "Gear Electives", min_courses: 1)
    create(:elective_group_course, elective_group: group, subject_code: "GEAR", course_number: 2000)
    create(:academic_profile, user: user, class_standing: "Sophomore", admit_term_uid: 202610)
    create(:student_program, :ended, user: user, name: "Old Major")
    sign_in user
    visit dashboard_programs_path
  end

  # Saves a screenshot for the pull request when SCREENSHOTS is set.
  def screenshot(name, selector = "main")
    return unless ENV["SCREENSHOTS"]

    # A tall window, so the element is not cut off at the bottom of the screen.
    page.driver.resize(1280, 3000)
    page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png").to_s, selector: selector)
    page.driver.resize(1280, 800)
  end

  it "shows the plan of a major against real terms" do
    expect(page).to have_text("not an official degree audit")
    card = find("#program-#{major.public_id}")

    card.find("summary", text: "Show the plan by term").click

    expect(card).to have_text("Year 3, fall: Fall 2027")
    expect(card).to have_text("WDGT 3000")
    screenshot("my-programs", "#program-#{major.public_id}")
  end

  it "confirms the assumed plan, then picks another plan" do
    card = find("#program-#{major.public_id}")
    expect(card).to have_text("Assumed")

    card.click_on("Confirm plan")

    expect(page).to have_text("Plan saved: Four Year Program.")
    card = find("#program-#{major.public_id}")
    expect(card).to have_text("Confirmed by you")

    card.select("Three Year Program", from: "Plan of study")
    card.click_on("Save plan")

    expect(page).to have_text("Plan saved: Three Year Program.")
    expect(major.reload.plan_name).to eq("Three Year Program")
  end

  it "plans a minor, shows the courses it adds, and removes it" do
    within("#plan-program-form") do
      select "Gear Minor", from: "Program"
      click_on "Plan this program"
    end

    expect(page).to have_text("Gear Minor added to your planned programs.")
    within("#planned-programs") do
      expect(page).to have_text("Courses it adds")
      expect(page).to have_text("Gear Electives: pick 1")
    end
    screenshot("my-programs-planned", "#planned-programs")

    accept_confirm { click_button("Remove Gear Minor") }

    expect(page).to have_text("Gear Minor removed from your planned programs.")
    expect(user.student_programs.planned).to be_empty
  end

  it "plans a Double Leopard pathway and removes it" do
    master = create(:degree_program, :master, slug: "widget-design-ms", name: "Widget Design, M.S.")
    create(:requirement_set, degree_program: master, catalog_year: catalog_year, name: "Widget Design, M.S.")
    pathway = create(:program_pathway, :double_leopard, name: "Widget Design, M.S. (Double Leopard)")
    create(:program_pathway_step, program_pathway: pathway, degree_program: master, position: 1, plan_years: 1)
    visit dashboard_programs_path

    within("#plan-pathway-form") do
      select pathway.name, from: "Pathway"
      click_on "Plan this pathway"
    end

    expect(page).to have_text("#{pathway.name} added to your planned programs.")
    within("#planned-programs") do
      expect(page).to have_css("#pathway-#{pathway.slug}")
      expect(page).to have_text("part of #{pathway.name}")
    end
    screenshot("my-programs-pathway", "#planned-programs")

    accept_confirm { click_button("Remove #{pathway.name}") }

    expect(page).to have_text("#{pathway.name} removed from your planned programs.")
    expect(user.student_programs.planned).to be_empty
  end

  it "lists the ended programs" do
    expect(find("#ended-programs")).to have_text("Old Major")
  end
end
