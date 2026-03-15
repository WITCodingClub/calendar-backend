# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Misc" do
  describe "GET /api/terms/active" do
    context "when 3 or more active terms exist" do
      let!(:active_term1) do
        create(:term,
               uid: 202501,
               year: 2025,
               season: :spring,
               start_date: Date.current.beginning_of_month,
               end_date: Date.current.end_of_month + 3.months)
      end
      let!(:active_term2) do
        create(:term,
               uid: 202502,
               year: 2025,
               season: :summer,
               start_date: Date.current.beginning_of_month + 1.month,
               end_date: Date.current.end_of_month + 4.months)
      end
      let!(:active_term3) do
        create(:term,
               uid: 202510,
               year: 2026,
               season: :fall,
               start_date: Date.current.beginning_of_month + 2.months,
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
               year: 2025,
               season: :spring,
               start_date: Date.current.beginning_of_month,
               end_date: Date.current.end_of_month + 2.months)
      end

      it "falls back to start_date for active check" do
        get "/api/terms/active"

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        # Should include term since start_date has passed
        expect(json["active_terms"]).to be_an(Array)
        expect(json["active_terms"].length).to eq(1)
        expect(json["active_terms"][0]["id"]).to eq(term_no_reg.uid)
      end
    end

    context "when terms have no dates" do
      let!(:term_no_dates) do
        create(:term,
               uid: 202501,
               year: 2025,
               season: :spring,
               start_date: nil,
               end_date: nil)
      end

      it "does not include terms without dates" do
        get "/api/terms/active"

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        expect(json["active_terms"]).to eq([])
      end
    end

    context "authentication" do
      it "does not require authentication" do
        get "/api/terms/active"

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
