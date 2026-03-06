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
      let!(:active_term4) do
        create(:term,
               uid: 202520,
               year: 2027,
               season: :spring,
               start_date: Date.current.beginning_of_month + 3.months,
               end_date: Date.current.end_of_month + 8.months)
      end

      before do
        # Create registration events for all terms that started before today
        create(:university_calendar_event, :registration,
               term: active_term1,
               summary: "Registration Opens - Spring 2025",
               start_time: Date.current - 1.month,
               end_time: Date.current - 1.month)
        create(:university_calendar_event, :registration,
               term: active_term2,
               summary: "Registration Opens - Summer 2025",
               start_time: Date.current - 2.weeks,
               end_time: Date.current - 2.weeks)
        create(:university_calendar_event, :registration,
               term: active_term3,
               summary: "Registration Opens - Fall 2026",
               start_time: Date.current - 1.week,
               end_time: Date.current - 1.week)
        create(:university_calendar_event, :registration,
               term: active_term4,
               summary: "Registration Opens - Spring 2027",
               start_time: Date.current - 1.day,
               end_time: Date.current - 1.day)
      end

      it "returns exactly 3 active terms" do
        get "/api/terms/active"

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        expect(json["active_terms"]).to be_an(Array)
        expect(json["active_terms"].length).to eq(3)
        
        json["active_terms"].each do |term|
          expect(term).to have_key("name")
          expect(term).to have_key("id")
          expect(term).to have_key("pub_id")
          expect(term).to have_key("start_date")
          expect(term).to have_key("end_date")
        end
      end
    end

    context "when 2 active terms exist" do
      let!(:active_term1) do
        create(:term,
               uid: 202501,
               year: 2025,
               season: :spring,
               start_date: Date.current.beginning_of_month,
               end_date: Date.current.end_of_month + 2.months)
      end
      let!(:active_term2) do
        create(:term,
               uid: 202502,
               year: 2025,
               season: :summer,
               start_date: Date.current.beginning_of_month + 1.month,
               end_date: Date.current.end_of_month + 3.months)
      end
      let!(:future_term) do
        create(:term,
               uid: 202510,
               year: 2026,
               season: :fall,
               start_date: Date.current + 4.months,
               end_date: Date.current + 8.months)
      end

      before do
        # Registration opened for both active terms
        create(:university_calendar_event, :registration,
               term: active_term1,
               summary: "Registration Opens",
               start_time: Date.current - 1.month,
               end_time: Date.current - 1.month)
        create(:university_calendar_event, :registration,
               term: active_term2,
               summary: "Registration Opens",
               start_time: Date.current - 2.weeks,
               end_time: Date.current - 2.weeks)
        # Registration not yet opened for future term
        create(:university_calendar_event, :registration,
               term: future_term,
               summary: "Registration Opens",
               start_time: Date.current + 3.months,
               end_time: Date.current + 3.months)
      end

      it "returns exactly 2 active terms" do
        get "/api/terms/active"

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        expect(json["active_terms"]).to be_an(Array)
        expect(json["active_terms"].length).to eq(2)
        
        term_ids = json["active_terms"].map { |t| t["id"] }
        expect(term_ids).to contain_exactly(active_term1.uid, active_term2.uid)
      end
    end

    context "when 1 active term exists" do
      let!(:active_term) do
        create(:term,
               uid: 202501,
               year: 2025,
               season: :spring,
               start_date: Date.current.beginning_of_month,
               end_date: Date.current.end_of_month + 2.months)
      end

      before do
        create(:university_calendar_event, :registration,
               term: active_term,
               summary: "Registration Opens",
               start_time: Date.current - 1.month,
               end_time: Date.current - 1.month)
      end

      it "returns single active term in array" do
        get "/api/terms/active"

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        expect(json["active_terms"]).to be_an(Array)
        expect(json["active_terms"].length).to eq(1)
        expect(json["active_terms"][0]["id"]).to eq(active_term.uid)
      end
    end

    context "when no active terms exist" do
      let!(:future_term) do
        create(:term,
               uid: 202501,
               year: 2025,
               season: :spring,
               start_date: Date.current + 2.months,
               end_date: Date.current + 6.months)
      end

      before do
        # Registration not yet open
        create(:university_calendar_event, :registration,
               term: future_term,
               summary: "Registration Opens",
               start_time: Date.current + 1.month,
               end_time: Date.current + 1.month)
      end

      it "returns empty array" do
        get "/api/terms/active"

        expect(response).to have_http_status(:ok)
        json = response.parsed_body

        expect(json["active_terms"]).to eq([])
      end
    end

    context "when terms have no registration events" do
      let!(:term_no_reg) do
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
