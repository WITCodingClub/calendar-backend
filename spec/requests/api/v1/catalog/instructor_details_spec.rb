# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Catalog instructor details", type: :request do
  def json = response.parsed_body

  let(:term) { create(:term) }
  let(:faculty) { create(:faculty) }

  before do
    create(:rating_distribution, faculty: faculty, r1: 1, r2: 0, r3: 2, r4: 3, r5: 4, total: 10)
    create(:teacher_rating_tag, faculty: faculty, tag_name: "Clear grading", tag_count: 7)
    create(:teacher_rating_tag, faculty: faculty, tag_name: "Tough grader", tag_count: 2)
    create(:rmp_rating, faculty: faculty, comment: "Great labs", rating_date: 1.day.ago)
    create(:rmp_rating, faculty: faculty, comment: nil)
  end

  it "returns the Rate My Professors distribution, tags, and recent reviews" do
    get "/api/v1/catalog/instructors/#{faculty.public_id}"

    data = json["data"]
    expect(data["rating_distribution"]).to eq("1" => 1, "2" => 0, "3" => 2, "4" => 3, "5" => 4)
    expect(data["rmp_tags"]).to eq([ { "name" => "Clear grading", "count" => 7 }, { "name" => "Tough grader", "count" => 2 } ])
    expect(data["recent_reviews"].pluck("comment")).to eq([ "Great labs" ])
    expect(data).to include("review_count" => 1, "reviews_source" => "ratemyprofessors.com")
    expect(data).not_to have_key("sections")
  end

  it "adds the sections taught in a term" do
    section = create(:course, term: term)
    section.faculties << faculty
    create(:course).faculties << faculty

    get "/api/v1/catalog/instructors/#{faculty.public_id}", params: { term_uid: term.uid }

    expect(json["data"]["sections"].pluck("crn")).to eq([ section.crn ])
  end

  it "answers 404 for an unknown term" do
    get "/api/v1/catalog/instructors/#{faculty.public_id}", params: { term_uid: 1 }

    expect(response).to have_http_status(:not_found)
  end

  it "has no distribution before any rating" do
    faculty.rating_distribution.update!(total: 0)

    get "/api/v1/catalog/instructors/#{faculty.public_id}"

    expect(json["data"]["rating_distribution"]).to be_nil
  end
end
