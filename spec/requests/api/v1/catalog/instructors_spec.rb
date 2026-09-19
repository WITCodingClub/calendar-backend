# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Catalog::Instructors", type: :request do
  include_context "catalog fixtures"

  def json = JSON.parse(response.body)

  describe "GET /api/v1/catalog/instructors" do
    it "lists only faculty who teach at least one section" do
      create(:faculty)
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

  describe "GET /api/v1/catalog/instructors/:pub_id/similar" do
    before do
      give_embedding(ada, 0.00)
      give_embedding(grace, 0.10)
    end

    it "returns the closest instructors who teach, nearest first" do
      get "/api/v1/catalog/instructors/#{ada.public_id}/similar"

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |i| i["name"] }).to eq([ "Grace Hop" ])
      expect(json["meta"]).to eq("pub_id" => ada.public_id, "limit" => 10)
    end

    it "returns an empty list for an instructor with no vector" do
      ada.update_columns(embedding: nil, embedding_digest: nil) # rubocop:disable Rails/SkipsModelValidations

      get "/api/v1/catalog/instructors/#{ada.public_id}/similar"

      expect(json["data"]).to be_empty
    end

    it "returns 404 for an instructor that does not exist" do
      get "/api/v1/catalog/instructors/fac_missing/similar"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "semantic search", :semantic_search do
    before do
      give_embedding(ada, 0.05)
      give_embedding(grace, 0.95)
      stub_openai_embeddings([ embedding_vector(0.0) ])
    end

    it "ranks the instructors that mean what the query means" do
      get "/api/v1/catalog/instructors", params: { q: "teaches computing", semantic: "true" }

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |i| i["name"] }).to eq([ "Ada Byron", "Grace Hop" ])
    end

    it "matches the literal name when semantic is not asked for" do
      get "/api/v1/catalog/instructors", params: { q: "byron" }

      expect(json["data"].map { |i| i["name"] }).to eq([ "Ada Byron" ])
      expect(a_request(:post, EmbeddingService::API_URL)).not_to have_been_made
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
