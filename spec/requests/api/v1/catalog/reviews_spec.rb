# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Catalog::Reviews", type: :request do
  def json = JSON.parse(response.body)
  def comments = json["data"].map { |review| review["comment"] }

  let(:ada) { create(:faculty, first_name: "Ada", last_name: "Byron") }

  let!(:group_work) do
    create(:rmp_rating, faculty: ada, course_name: "COMP1050", clarity_rating: 5, difficulty_rating: 2,
                        would_take_again: true, rating_tags: "Group projects--Caring",
                        thumbs_up_total: 3, thumbs_down_total: 1,
                        comment: "Lots of group projects.", rating_date: 2.days.ago)
  end

  let!(:tough_exams) do
    create(:rmp_rating, faculty: ada, course_name: "COMP2000", clarity_rating: 2,
                        comment: "The exams are brutal.", rating_date: 1.day.ago)
  end

  describe "GET /api/v1/catalog/reviews" do
    it "returns reviews, newest first, with pagination metadata" do
      get "/api/v1/catalog/reviews"

      expect(response).to have_http_status(:ok)
      expect(comments).to eq([ "The exams are brutal.", "Lots of group projects." ])
      expect(json["meta"]).to include("page" => 1, "per_page" => 25, "total_count" => 2, "total_pages" => 1)
    end

    it "serializes the full review payload" do
      get "/api/v1/catalog/reviews", params: { q: "group projects" }

      review = json["data"].first
      expect(review).to include(
        "course_name"       => "COMP1050",
        "comment"           => "Lots of group projects.",
        "clarity_rating"    => 5,
        "difficulty_rating" => 2,
        "would_take_again"  => true,
        "sentiment"         => "positive",
        "tags"              => [ "Group projects", "Caring" ],
        "thumbs_up"         => 3,
        "thumbs_down"       => 1,
        "source"            => "ratemyprofessors.com"
      )
      expect(review["instructor"]).to eq("pub_id" => ada.public_id, "name" => "Ada Byron")
      expect(review["pub_id"]).to be_present
    end

    it "names the source in the metadata, so a client can credit it" do
      get "/api/v1/catalog/reviews"

      expect(json["meta"]["source"]).to eq("ratemyprofessors.com")
    end

    it "keeps one instructor's reviews" do
      create(:rmp_rating, comment: "Someone else's class.")

      get "/api/v1/catalog/reviews", params: { instructor: ada.public_id }

      expect(json["meta"]["total_count"]).to eq(2)
    end

    it "keeps the negative reviews" do
      get "/api/v1/catalog/reviews", params: { sentiment: "negative" }

      expect(comments).to eq([ "The exams are brutal." ])
    end

    it "returns 400 for an instructor that does not exist" do
      get "/api/v1/catalog/reviews", params: { instructor: "fac_nobody" }

      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("INVALID_FILTER")
    end

    it "caps the page size" do
      get "/api/v1/catalog/reviews", params: { per_page: 5000 }

      expect(json["meta"]["per_page"]).to eq(100)
    end

    describe "by meaning", :semantic_search do
      it "ranks the reviews that mean what the query means" do
        give_embedding(group_work, 0.05)
        give_embedding(tough_exams, 0.95)
        stub_openai_embeddings([ embedding_vector(0.0) ])

        get "/api/v1/catalog/reviews", params: { q: "team assignments", semantic: "true" }

        expect(comments).to eq([ "Lots of group projects.", "The exams are brutal." ])
      end
    end
  end
end
