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

    it "shows the section's Banner fields and its cross-listed sections" do
      course = create(:course, :cross_listed, term: term, part_of_term: "FA1", campus: "Boston Main Campus",
                                              seats_capacity: 30, seats_available: 5, waitlist_capacity: 10, waitlist_available: 10)
      partner = create(:course, :cross_listed, term: term)

      get admin_course_path(course)

      expect(response.body).to include("FA1", "Boston Main Campus", "5 of 30 open", "10 of 10 open",
                                       %(href="#{admin_course_path(partner)}"), "4 of 24 open across the group")
    end

    it "shows the catalog entry, fees, restrictions, learning objectives, and mutual exclusions" do
      course = create(:course, term: term, subject: "Architecture (ARCH)", course_number: 4100)
      create(:catalog_course, :with_details, subject_code: "ARCH", course_number: 4100,
                                             college: "School of Architecture and Design", division: "Undergraduate",
                                             department: "Architecture", levels: %w[Undergraduate Graduate],
                                             grading_modes: [ "Standard Letter" ],
                                             fees: [ { "level" => "Undergraduate", "description" => "Studio Fee", "amount_cents" => 15_000 } ],
                                             restrictions: [ { "heading" => "Must be enrolled in one of the following Levels", "values" => [ "Undergraduate" ] } ],
                                             learning_objectives: "Draw a plan.\nBuild a model.",
                                             mutual_exclusions: [ { "subject_code" => "ARCH", "course_number" => 6100 } ])

      get admin_course_path(course)

      expect(response.body).to include("School of Architecture and Design", "Undergraduate, Graduate", "Standard Letter",
                                       "Studio Fee (Undergraduate): $150.00", "Must be enrolled in one of the following Levels",
                                       "<p>Draw a plan.\n<br />Build a model.</p>", "ARCH 6100")
    end

    it "says when the course has no catalog details" do
      course = create(:course, term: term)

      get admin_course_path(course)

      expect(response.body).to include("No catalog details for this course yet")
    end
  end
end
