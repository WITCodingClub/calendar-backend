# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Catalog::Subjects", type: :request do
  include_context "catalog fixtures"

  def json = JSON.parse(response.body)

  describe "GET /api/v1/catalog/subjects" do
    it "lists subjects with their section counts" do
      get "/api/v1/catalog/subjects"

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to eq([
        { "subject" => "Computer Science (COMP)", "code" => "COMP", "section_count" => 3 },
        { "subject" => "Mathematics (MATH)",      "code" => "MATH", "section_count" => 1 }
      ])
      expect(json["meta"]["count"]).to eq(2)
    end

    it "narrows to one term" do
      get "/api/v1/catalog/subjects", params: { term_uid: 202_620 }

      expect(json["data"].map { |s| s["code"] }).to eq([ "MATH" ])
      expect(json["meta"]["term_uid"]).to eq(202_620)
    end

    it "excludes cancelled sections from the counts" do
      get "/api/v1/catalog/subjects", params: { term_uid: 202_710 }

      comp = json["data"].find { |s| s["code"] == "COMP" }
      expect(comp["section_count"]).to eq(3)
    end
  end
end
