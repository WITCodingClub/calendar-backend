# frozen_string_literal: true

require "rails_helper"

# Issue #448: the prerequisite map on a course page. Select a course in the
# map, and its page shows its own map.
RSpec.describe "Prerequisite map", type: :system do
  def ref(subject_code, course_number) = { "type" => "course", "subject_code" => subject_code, "course_number" => course_number }

  before do
    create(:catalog_course, subject_code: "MATH", course_number: 1750, title: "Engineering Calculus I")
    create(:catalog_course, subject_code: "COMP", course_number: 1000, title: "Computer Science I")
    create(:catalog_course, subject_code: "COMP", course_number: 1050, title: "Computer Science II", prerequisites: ref("COMP", 1000))
    create(:catalog_course, subject_code: "MATH", course_number: 2300, title: "Discrete Mathematics", prerequisites: ref("MATH", 1750))
    structures = create(:catalog_course, subject_code: "COMP", course_number: 2000, title: "Data Structures",
                                         prerequisites: { "type" => "and", "operands" => [
                                           ref("COMP", 1050),
                                           { "type" => "or", "operands" => [ ref("MATH", 2300), ref("MATH", 1750) ] }
                                         ] })
    create(:course_prerequisite, catalog_course: structures, required_catalog_course: CatalogCourse.find_by_code("COMP1050"))
    %w[3000 3350 3450].each do |number|
      later = create(:catalog_course, subject_code: "COMP", course_number: number.to_i, prerequisites: ref("COMP", 2000))
      create(:course_prerequisite, catalog_course: later, required_catalog_course: structures)
    end

    sign_in create(:user)
  end

  # Saves a screenshot for the pull request when SCREENSHOTS is set.
  def screenshot(name)
    return unless ENV["SCREENSHOTS"]

    page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png").to_s, selector: "#prerequisite-map")
  end

  it "moves to the map of the course that the student selects" do
    visit dashboard_course_path("COMP2000")

    within("#prerequisite-map") do
      expect(page).to have_css("[aria-current='page']", text: "COMP 2000")
      expect(page).to have_link("COMP 3450")
      screenshot("prerequisite-map")

      click_link "COMP 1050"
    end

    within("#prerequisite-map") do
      expect(page).to have_css("[aria-current='page']", text: "COMP 1050")
      expect(page).to have_link("COMP 1000")
      expect(page).to have_link("COMP 2000")
      expect(page).to have_no_link("COMP 3450")
    end
  end
end
