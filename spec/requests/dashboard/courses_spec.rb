# frozen_string_literal: true

require "rails_helper"

# Issue #797: the course catalog, read-only, for any signed-in user.
RSpec.describe "Dashboard::Courses", type: :request do
  let(:user) { create(:user) }
  let(:page) { Nokogiri::HTML(response.body) }
  let(:term) { create(:term) }
  let!(:comp1050) { create(:catalog_course, subject_code: "COMP", course_number: 1050, title: "Computer Science II") }
  let!(:comp2000) do
    create(:catalog_course, :with_details, subject_code: "COMP", course_number: 2000, title: "Data Structures",
                                           prerequisites: {
                                             "type" => "or",
                                             "operands" => [
                                               { "type" => "course", "subject_code" => "COMP", "course_number" => 1050, "min_grade" => "D" },
                                               { "type" => "course", "subject_code" => "COMP", "course_number" => 128 }
                                             ]
                                           },
                                           restrictions: [ { "heading" => "Cannot be enrolled in", "values" => [ "WFD" ] } ],
                                           fees: [ { "description" => "Lab fee", "amount_cents" => 15_000 } ])
  end

  before { sign_in user }

  describe "GET /dashboard/courses" do
    it "lists the catalog for a user with no processed courses" do
      get dashboard_courses_path

      expect(response).to have_http_status(:ok)
      expect(page.css("#courses a").map { |link| link.at_css("span span").text }).to eq([ "COMP 1050: Computer Science II", "COMP 2000: Data Structures" ])
    end

    it "finds a course by its code" do
      get dashboard_courses_path, params: { q: "comp 2000" }

      expect(page.css("#courses a").pluck("href")).to eq([ "/dashboard/courses/COMP2000" ])
    end

    it "shows only the courses offered in the chosen term" do
      create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000)

      get dashboard_courses_path, params: { term_uid: term.uid }

      expect(page.css("#courses a").pluck("href")).to eq([ "/dashboard/courses/COMP2000?term_uid=#{term.uid}" ])
    end

    it "shows an empty state when nothing matches" do
      get dashboard_courses_path, params: { q: "underwater basket weaving" }

      expect(page.at_css("[data-empty-state]").text).to include("No courses match.")
    end

    it "answers 404 for an unknown term" do
      get dashboard_courses_path, params: { term_uid: 1 }

      expect(response).to have_http_status(:not_found)
    end

    it "pages the list" do
      create_list(:catalog_course, Dashboard::CatalogPages::PER_PAGE, subject_code: "MATH")

      get dashboard_courses_path, params: { page: 2 }

      expect(page.css("#courses a").size).to eq(2)
      expect(page.at_css("nav[aria-label='Pagination']").text).to include("Page 2 of 2")
      expect(page.at_css("a[rel='prev']")["href"]).to eq(dashboard_courses_path)
    end
  end

  describe "GET /dashboard/courses/:code" do
    it "shows the description, prerequisites, restrictions, and fees" do
      get dashboard_course_path("COMP2000")

      about = page.at_css("#about")
      expect(about.text).to include(comp2000.description, "Cannot be enrolled in:", "WFD", "Lab fee: $150.00", "(min D)")
      expect(about.css("a").pluck("href")).to include("/dashboard/courses/COMP1050")
      expect(about.text).to include("COMP 128")
    end

    it "shows the sections of the current term with their instructors" do
      allow(Term).to receive(:current).and_return(term)
      faculty = create(:faculty, first_name: "Ada", last_name: "Lovelace")
      section = create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000,
                                seats_capacity: 30, seats_available: 12)
      section.faculties << faculty

      get dashboard_course_path("COMP2000")

      row = page.at_css("#sections [data-crn='#{section.crn}']")
      expect(row.text).to include("COMP 2000-01", "12 of 30 open", "Ada Lovelace")
      expect(row.at_css("a")["href"]).to eq(dashboard_instructor_path(faculty.public_id))
    end

    it "picks the newest term with a section when the current term has none" do
      older = create(:term)
      create(:course, term: older, subject: "COMP", course_number: 2000)

      get dashboard_course_path("COMP2000")

      expect(page.at_css("#sections h2").text).to eq("Sections in #{older.name}")
    end

    it "says so when no term has a section" do
      get dashboard_course_path("COMP1050")

      expect(page.at_css("#sections [data-empty-state]").text).to include("No sections on record.")
    end

    it "accepts a code with a space" do
      get dashboard_course_path("COMP 2000")

      expect(response).to have_http_status(:ok)
    end

    it "answers 404 for an unknown course" do
      get dashboard_course_path("COMP9999")

      expect(response).to have_http_status(:not_found)
    end
  end
end
