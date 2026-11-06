# frozen_string_literal: true

require "rails_helper"

# Issue #797: the instructors of the catalog, read-only, for any signed-in user.
RSpec.describe "Dashboard::Instructors", type: :request do
  let(:user) { create(:user) }
  let(:page) { Nokogiri::HTML(response.body) }
  let(:term) { create(:term) }
  let(:ada) { create(:faculty, first_name: "Ada", last_name: "Lovelace", department: "Computer Science", email: "ada-797@wit.edu", phone: "555-0100") }
  let(:alan) { create(:faculty, first_name: "Alan", last_name: "Turing") }

  before do
    create(:course, term: term).faculties << ada
    create(:course, term: create(:term)).faculties << alan
    create(:faculty, first_name: "Staff", last_name: "Member")
    sign_in user
  end

  describe "GET /dashboard/instructors" do
    it "lists only the faculty who teach a section" do
      get dashboard_instructors_path

      expect(response).to have_http_status(:ok)
      expect(page.css("#instructors a").map { |link| link.at_css("span span").text }).to eq([ "Ada Lovelace", "Alan Turing" ])
    end

    it "finds an instructor by name" do
      get dashboard_instructors_path, params: { q: "turing" }

      expect(page.css("#instructors a").map { |link| link.at_css("span span").text }).to eq([ "Alan Turing" ])
    end

    it "shows only the instructors teaching in the chosen term" do
      get dashboard_instructors_path, params: { term_uid: term.uid }

      expect(page.css("#instructors a").pluck("href")).to eq([ dashboard_instructor_path(ada.public_id, term_uid: term.uid) ])
    end

    it "shows the rating summary" do
      create(:rating_distribution, faculty: ada, avg_rating: 4.2, num_ratings: 31)
      ada.update!(rmp_id: "VGVhY2hlci0xMjM0NQ==")

      get dashboard_instructors_path

      expect(page.at_css("#instructors").text).to include("Computer Science · 4.2 / 5 from 31 ratings")
    end
  end

  describe "GET /dashboard/instructors/:id" do
    it "shows the ratings, reviews, and a link to Rate My Professors" do
      create(:rating_distribution, faculty: ada, avg_rating: 4.2, avg_difficulty: 3.1, num_ratings: 31, would_take_again_percent: 87.5)
      create(:rmp_rating, faculty: ada, comment: "Clear lectures and fair exams.")
      ada.update!(rmp_id: "VGVhY2hlci0xMjM0NQ==")

      get dashboard_instructor_path(ada.public_id)

      ratings = page.at_css("#ratings")
      expect(ratings.text).to include("4.2", "3.1", "88%", "31", "Clear lectures and fair exams.")
      expect(ratings.at_css("a[target='_blank']")["href"]).to eq("https://www.ratemyprofessors.com/professor/12345")
    end

    it "does not show the email or phone number" do
      get dashboard_instructor_path(ada.public_id)

      expect(response.body).not_to include("ada-797@wit.edu", "555-0100")
    end

    it "says so when there are no ratings" do
      get dashboard_instructor_path(alan.public_id)

      expect(page.at_css("#ratings").text).to include("No ratings yet.")
    end

    it "shows the sections of the newest term the instructor teaches in" do
      get dashboard_instructor_path(ada.public_id)

      expect(page.at_css("#sections h2").text).to eq("Sections in #{term.name}")
      expect(page.css("#sections [data-crn]").size).to eq(1)
    end

    it "answers 404 for an unknown instructor" do
      get dashboard_instructor_path("nope")

      expect(response).to have_http_status(:not_found)
    end
  end
end
