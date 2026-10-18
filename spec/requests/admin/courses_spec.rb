# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin courses", type: :request do
  let(:admin) { create(:user, :super_admin) }
  let(:term)  { create(:term) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    sign_in admin
  end

  describe "GET /admin/courses/:id" do
    it "shows the prerequisites, corequisites, unlocked courses, and linked sections" do
      course = create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2650,
                               links_fetched_at: Time.current)
      prereq = create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000)
      tree = { "type" => "or", "operands" => [
        { "type" => "course", "subject_code" => "COMP", "course_number" => 2000, "min_grade" => "C" },
        { "type" => "course", "subject_code" => "COMP", "course_number" => 128 }
      ] }
      catalog = create(:catalog_course, subject_code: "COMP", course_number: 2650, prerequisites: tree,
                                        corequisites: [ { "subject_code" => "MATH", "course_number" => 2300 } ])
      later = create(:catalog_course, subject_code: "COMP", course_number: 3450)
      create(:course_prerequisite, catalog_course: later, required_catalog_course: catalog)
      lab = create(:section_link, course: course).linked_course

      get admin_course_path(course)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{admin_course_path(prereq)}"), "COMP 128", "min C",
                                       "MATH 2300", "COMP 3450", %(href="#{admin_course_path(lab)}"))
    end

    it "says when the course has no catalog details" do
      course = create(:course, term: term)

      get admin_course_path(course)

      expect(response.body).to include("No catalog details for this course yet")
    end
  end
end
