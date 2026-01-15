# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Misc" do
  describe "GET /api/terms/current_and_next" do
    context "when current and next terms exist" do
      let!(:current_term) do
        create(:term,
               uid: 202501,
               year: Date.current.year,
               season: :spring,
               start_date: Date.current.beginning_of_month - 1.month,
               end_date: Date.current.end_of_month + 2.months)
      end
      let!(:next_term) do
        create(:term,
               uid: 202502,
               year: Date.current.year,
               season: :summer,
               start_date: Date.current.end_of_month + 3.months,
               end_date: Date.current.end_of_month + 6.months)
      end

      it "returns both current and next term information" do
        get "/api/terms/current_and_next"

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        expect(json["current_term"]).to include(
          "name"   => current_term.name,
          "id"     => current_term.uid,
          "pub_id" => current_term.public_id
        )
        expect(json["current_term"]).to have_key("start_date")
        expect(json["current_term"]).to have_key("end_date")

        expect(json["next_term"]).to include(
          "name"   => next_term.name,
          "id"     => next_term.uid,
          "pub_id" => next_term.public_id
        )
      end
    end

    context "when only current term exists" do
      let!(:current_term) do
        create(:term,
               uid: 202501,
               year: Date.current.year,
               season: :spring,
               start_date: Date.current.beginning_of_month - 1.month,
               end_date: Date.current.end_of_month + 2.months)
      end

      it "returns current term and null for next term" do
        get "/api/terms/current_and_next"

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        expect(json["current_term"]).to be_present
        expect(json["next_term"]).to be_nil
      end
    end

    context "when no terms exist" do
      it "returns null for both terms" do
        get "/api/terms/current_and_next"

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        expect(json["current_term"]).to be_nil
        expect(json["next_term"]).to be_nil
      end
    end

    context "authentication" do
      it "does not require authentication" do
        get "/api/terms/current_and_next"

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
