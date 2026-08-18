# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Catalog::Terms", type: :request do
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
    end
  end
end
