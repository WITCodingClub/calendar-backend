# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Catalog::Instructors", type: :request do
  include_context "catalog fixtures"

  def json = JSON.parse(response.body)

  describe "GET /api/v1/catalog/instructors" do
    it "lists only faculty who teach at least one section" do
      Faculty.create!(first_name: "Unassigned", last_name: "Person", email: "nobody@wit.edu")
      get "/api/v1/catalog/instructors"

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |i| i["last_name"] }).to eq(%w[Byron Hop])
      expect(json["meta"]["total_count"]).to eq(2)
    end

    it "counts each instructor once even when they teach several sections" do
      get "/api/v1/catalog/instructors", params: { q: "byron" }

      expect(json["data"].size).to eq(1)
      expect(json["meta"]["total_count"]).to eq(1)
    end

    it "narrows to one term" do
      get "/api/v1/catalog/instructors", params: { term_uid: 202_620 }

      expect(json["data"]).to be_empty
    end
  end

  describe "GET /api/v1/catalog/instructors/:pub_id" do
    it "returns the instructor without contact details" do
      get "/api/v1/catalog/instructors/#{ada.public_id}"

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include(
        "name" => "Ada Byron", "title" => "Professor",
        "school" => "School of Computing & Data Science"
      )
      expect(json["data"].keys).not_to include("email", "phone", "office_location")
    end

    it "returns a structured 404 for an unknown public id" do
      get "/api/v1/catalog/instructors/fac_nope"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
