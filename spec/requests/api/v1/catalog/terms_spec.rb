# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Catalog::Terms", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  include_context "catalog fixtures"

  def json = JSON.parse(response.body)

  describe "GET /api/v1/catalog/terms" do
    before { get "/api/v1/catalog/terms" }

    it "returns every term, newest first" do
      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |t| t["uid"] }).to eq([ 202_710, 202_620 ])
      expect(json["meta"]["count"]).to eq(2)
    end

    it "counts only active sections" do
      fall = json["data"].find { |t| t["uid"] == 202_710 }
      expect(fall["section_count"]).to eq(3)
      expect(fall["name"]).to eq("Fall 2026")
      expect(fall["season"]).to eq("fall")
    end

    it "is publicly cacheable" do
      expect(response.headers["Cache-Control"]).to include("public")
      expect(response.headers["Cache-Control"]).to include("max-age=3600")
    end
  end

  describe "GET /api/v1/catalog/terms/:uid" do
    it "returns the one term" do
      get "/api/v1/catalog/terms/202710"

      expect(response).to have_http_status(:ok)
      expect(json["data"]["uid"]).to eq(202_710)
      expect(json["data"]["section_count"]).to eq(3)
    end

    it "returns a structured 404 for an unknown term" do
      get "/api/v1/catalog/terms/999999"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
      expect(json["error"]).to eq("No term 999999")
    end
  end

  describe "GET /api/v1/catalog/terms?active=true" do
    it "lists only the terms in session today" do
      fall_term.update!(start_date: Date.new(2026, 9, 2), end_date: Date.new(2026, 12, 18))
      spring_term.update!(start_date: Date.new(2026, 1, 7), end_date: Date.new(2026, 4, 30))

      travel_to(Date.new(2026, 10, 8)) { get "/api/v1/catalog/terms", params: { active: "true" } }

      expect(json["data"].map { |t| t["uid"] }).to eq([ 202_710 ])
    end
  end

  describe "GET /api/v1/catalog/terms/current" do
    it "returns the term in session" do
      travel_to(Date.new(2026, 10, 8)) { get "/api/v1/catalog/terms/current" }

      expect(response).to have_http_status(:ok)
      expect(json["data"]["uid"]).to eq(202_710)
      expect(json["data"]["section_count"]).to eq(3)
    end
  end

  describe "GET /api/v1/catalog/terms/next" do
    it "returns the term after the current term" do
      create(:term, uid: 202_720, year: 2027, season: :spring)

      travel_to(Date.new(2026, 10, 8)) { get "/api/v1/catalog/terms/next" }

      expect(response).to have_http_status(:ok)
      expect(json["data"]["uid"]).to eq(202_720)
    end

    it "answers NOT_FOUND when the next term is not in the catalog yet" do
      travel_to(Date.new(2026, 10, 8)) { get "/api/v1/catalog/terms/next" }

      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "No next term", "code" => "NOT_FOUND")
    end
  end
end
