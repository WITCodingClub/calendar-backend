# frozen_string_literal: true

require "rails_helper"

# Issue #797: the finals schedule of a term, read-only, for any signed-in user.
RSpec.describe "Dashboard::Finals", type: :request do
  let(:user) { create(:user) }
  # A method, not a let: one example makes several requests.
  def page = Nokogiri::HTML(response.body)
  let(:term) { create(:term) }
  let(:mine) { create(:course, term: term, subject: "Computer Science (COMP)", course_number: 2000, title: "Data Structures") }
  let(:other) { create(:course, term: term, subject: "MATH", course_number: 1800, title: "Calculus I") }

  before { sign_in user }

  def crns = page.css("#finals [data-crn]").map { |row| row["data-crn"].to_i }

  context "with no finals schedule" do
    it "shows an empty state" do
      get dashboard_finals_path

      expect(response).to have_http_status(:ok)
      expect(page.at_css("[data-empty-state]").text).to include("No finals schedule yet.")
    end
  end

  context "with a finals schedule" do
    let!(:my_exam) { create(:final_exam, term: term, course: mine, crn: mine.crn, exam_date: Date.new(2026, 12, 15), location: "WENTW 010") }
    let!(:other_exam) { create(:final_exam, term: term, course: other, crn: other.crn, exam_date: Date.new(2026, 12, 16)) }

    before { create(:enrollment, user: user, course: mine, term: term) }

    it "lists every exam by day and marks the user's own" do
      get dashboard_finals_path

      expect(crns).to eq([ my_exam.crn, other_exam.crn ])
      expect(page.at_css("[data-crn='#{my_exam.crn}']").text).to include("Yours", "8:00 AM", "WENTW 010")
      expect(page.at_css("[data-crn='#{other_exam.crn}']").text).not_to include("Yours")
      expect(page.at_css("#finals").text).to include("Tuesday, December 15")
    end

    it "shows only the user's exams with mine=1" do
      get dashboard_finals_path, params: { mine: "1" }

      expect(crns).to eq([ my_exam.crn ])
    end

    it "finds an exam by course code, title word, or CRN" do
      get dashboard_finals_path, params: { q: "MATH 1800" }
      expect(crns).to eq([ other_exam.crn ])

      get dashboard_finals_path, params: { q: "comp 2000" }
      expect(crns).to eq([ my_exam.crn ])

      get dashboard_finals_path, params: { q: "calculus" }
      expect(crns).to eq([ other_exam.crn ])

      get dashboard_finals_path, params: { q: other_exam.crn.to_s }
      expect(crns).to eq([ other_exam.crn ])
    end

    it "links a row to the course page only when the catalog has the course" do
      create(:catalog_course, subject_code: "COMP", course_number: 2000)

      get dashboard_finals_path

      expect(page.at_css("[data-crn='#{my_exam.crn}'] a")["href"]).to eq("/dashboard/courses/COMP2000?term_uid=#{term.uid}")
      expect(page.at_css("[data-crn='#{other_exam.crn}'] a")).to be_nil
    end

    it "shows a CRN for an exam with no course" do
      create(:final_exam, term: term, crn: 55_555)

      get dashboard_finals_path

      expect(page.at_css("[data-crn='55555']").text).to include("CRN 55555")
    end

    it "says the user has no courses when mine=1 finds nothing" do
      Enrollment.delete_all

      get dashboard_finals_path, params: { mine: "1" }

      expect(page.at_css("[data-empty-state]").text).to include("None of your courses", "browser extension")
    end
  end
end
