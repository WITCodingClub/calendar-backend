# frozen_string_literal: true

require "rails_helper"

# Issue #655: every admin index and show page renders through the shared
# partials. A broken partial fails here. Each page has two or more rows, so
# a page that runs one query for each row shows up in the query logs (#689).
RSpec.describe "Admin pages", type: :request do
  let(:owner) { create(:user, access_level: :owner, first_name: "Olive", last_name: "Owner") }
  let(:page) { Nokogiri::HTML(response.body) }

  let(:known_controllers) do
    Rails.root.glob("app/javascript/controllers/**/*_controller.js").map do |path|
      path.relative_path_from(Rails.root.join("app/javascript/controllers")).to_s
        .delete_suffix("_controller.js").tr("_", "-").gsub("/", "--")
    end
  end

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    stub_request(:get, %r{\Ahttps://selfservice\.wit\.edu/StudentRegistrationSsb/ssb/courseSearch/getTerms})
      .to_return(status: 200, body: [ { code: "202620", description: "Spring 2026" } ].to_json,
                 headers: { "Content-Type" => "application/json" })
    allow(TwentyFiveLiveSyncJob).to receive(:in_progress?).and_return(false)
    sign_in owner
  end

  # The page renders, has one h1, and names only Stimulus controllers that exist.
  def expect_admin_page(heading)
    expect(response).to have_http_status(:ok)
    expect(page.css("main h1").map { |h1| h1.text.strip }).to eq([ heading ])
    used = page.css("[data-controller]").flat_map { |node| node["data-controller"].split }
    expect(used - known_controllers).to be_empty
  end

  let(:term) { create(:term) }
  let(:faculty) { create(:faculty, first_name: "Ada", last_name: "Lovelace") }
  let(:building) { create(:building) }
  let(:room) { create(:room, building: building) }

  let(:course) do
    create(:course, term: term, title: "Data Structures").tap do |course|
      course.faculties << faculty
      meeting_time = create(:course_meeting_time, course: course)
      meeting_time.rooms << room
    end
  end

  describe "the dashboard" do
    it "renders" do
      get admin_root_path

      expect_admin_page("Dashboard")
    end
  end

  describe "users" do
    let(:student) { create(:user, first_name: "Sam", last_name: "Student") }

    before do
      create(:enrollment, user: student, course: course, term: term)
      create(:user)
    end

    it "renders the index" do
      get admin_users_path

      expect_admin_page("Users")
      expect(response.body).to include("Sam Student")
    end

    it "renders the show page with enrollments and the delete dialog" do
      get admin_user_path(student)

      expect_admin_page("Sam Student")
      expect(response.body).to include("Data Structures")
      expect(page.at_css("dialog [data-type-to-confirm-target='submit']")["disabled"]).to eq("disabled")
    end

    it "renders the edit form" do
      get edit_admin_user_path(student)

      expect_admin_page("Edit Sam Student")
    end
  end

  describe "courses" do
    before do
      course
      create(:course, term: term)
    end

    it "renders the index" do
      get admin_courses_path

      expect_admin_page("Courses")
      expect(response.body).to include("Data Structures")
    end

    it "renders the show page" do
      create_list(:enrollment, 2, course: course, term: term)

      get admin_course_path(course)

      expect_admin_page("#{course.subject} #{course.course_number}")
      expect(response.body).to include("Ada Lovelace")
    end
  end

  describe "the course catalog" do
    it "renders" do
      term

      get admin_course_catalog_path

      expect_admin_page("Course Catalog")
      expect(response.body).to include("Spring 2026")
    end
  end

  describe "terms" do
    before do
      course
      create(:course, term: term)
      create(:term)
    end

    it "renders the index" do
      get admin_terms_path

      expect_admin_page("Terms")
    end

    it "renders the show page" do
      get admin_term_path(term)

      expect_admin_page(term.name)
      expect(response.body).to include("Data Structures")
    end
  end

  describe "buildings" do
    it "renders the index with a room count for each building" do
      create_list(:room, 2, building: building)
      create(:room)

      get admin_buildings_path

      expect_admin_page("Buildings")
      expect(page.css("td[data-label='Rooms']").map { |td| td.text.strip }).to contain_exactly("2", "1")
    end
  end

  describe "rooms" do
    before do
      course
      create(:room, building: building)
    end

    it "renders the index" do
      get admin_rooms_path

      expect_admin_page("Rooms")
    end

    it "renders the show page" do
      get admin_room_path(room)

      expect_admin_page("Room #{room.number}")
      expect(response.body).to include("Data Structures")
    end
  end

  describe "faculty" do
    before do
      course
      create(:faculty)
    end

    it "renders the index" do
      get admin_faculties_path

      expect_admin_page("Faculty & Staff")
      expect(response.body).to include("Ada Lovelace")
    end

    it "renders the show page" do
      get admin_faculty_path(faculty)

      expect_admin_page("Ada Lovelace")
      expect(response.body).to include("Data Structures")
    end

    it "renders the directory status page" do
      get directory_status_admin_faculties_path

      expect_admin_page("Directory Sync Status")
    end

    it "renders missing RMP IDs with a course count for each professor" do
      other = create(:faculty, first_name: "Grace", last_name: "Hopper")
      2.times { create(:course, term: term).faculties << other }

      get missing_rmp_ids_admin_faculties_path

      expect_admin_page("Professors Missing RMP IDs")
      counts = page.css("td[data-label='Courses']").map { |td| td.text.strip }
      expect(counts).to contain_exactly("1", "2")
    end
  end

  describe "RMP ratings" do
    it "renders the index" do
      create_list(:rmp_rating, 2, faculty: faculty)

      get admin_rmp_ratings_path

      expect_admin_page("Rate My Professor Ratings")
    end
  end

  describe "finals schedules" do
    let!(:schedule) { create(:finals_schedule, term: term, uploaded_by: owner) }

    before do
      create(:finals_schedule)
      create_list(:final_exam, 2, term: term)
    end

    it "renders the index" do
      get admin_finals_schedules_path

      expect_admin_page("Finals Schedules")
    end

    it "renders the show page" do
      get admin_finals_schedule_path(schedule)

      expect_admin_page("Finals Schedule: #{term.name}")
    end

    it "renders the upload form" do
      get new_admin_finals_schedule_path

      expect_admin_page("Upload Finals Schedule")
    end
  end

  describe "calendars" do
    it "renders the index" do
      create_list(:course_calendar, 2)

      get admin_calendars_path

      expect_admin_page("Calendars")
    end
  end

  describe "calendar events" do
    it "renders the index" do
      create_list(:calendar_event, 2)

      get admin_calendar_events_path

      expect_admin_page("Calendar Events")
    end
  end

  describe "university calendar events" do
    let!(:event) { create(:university_calendar_event, summary: "Spring Break", location: "Campus") }

    before { create(:university_calendar_event, location: "Campus") }

    it "renders the index" do
      get admin_university_calendar_events_path

      expect_admin_page("University Calendar Events")
      expect(response.body).to include("Spring Break")
    end

    it "renders the show page" do
      get admin_university_calendar_event_path(event)

      expect_admin_page("Spring Break")
    end
  end

  describe "the service account" do
    it "renders" do
      get admin_service_account_index_path

      expect_admin_page("Service Account")
    end
  end
end
