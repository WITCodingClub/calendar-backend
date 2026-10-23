# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/api/user/backfills", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  describe "GET" do
    it "reports every backfill as not completed before the extension marks one" do
      get "/api/user/backfills", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "past_terms"    => { "completed" => false, "completed_at" => nil },
        "academic_data" => { "completed" => false, "completed_at" => nil }
      )
    end

    it "reports a completed backfill with its time" do
      row = create(:user_backfill, user: user, name: "academic_data")

      get "/api/user/backfills", headers: auth_headers_for(user)

      expect(response.parsed_body).to include(
        "past_terms"    => { "completed" => false, "completed_at" => nil },
        "academic_data" => { "completed" => true, "completed_at" => row.completed_at.iso8601 }
      )
    end

    it "does not show the backfills of another user" do
      create(:user_backfill, name: "past_terms")

      get "/api/user/backfills", headers: auth_headers_for(user)

      expect(response.parsed_body.dig("past_terms", "completed")).to be(false)
    end
  end

  describe "PUT /:name" do
    it "marks the backfill completed and returns every backfill" do
      freeze_time do
        put "/api/user/backfills/past_terms", headers: auth_headers_for(user), as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(
          "past_terms"    => { "completed" => true, "completed_at" => Time.current.iso8601 },
          "academic_data" => { "completed" => false, "completed_at" => nil }
        )
      end
    end

    it "keeps one row when the extension marks the same backfill twice" do
      2.times { put "/api/user/backfills/academic_data", headers: auth_headers_for(user), as: :json }

      expect(response).to have_http_status(:ok)
      expect(user.user_backfills.where(name: "academic_data").count).to eq(1)
    end

    it "answers 404 for a name it does not know" do
      put "/api/user/backfills/grades", headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("past_terms, academic_data")
      expect(user.user_backfills).to be_empty
    end
  end
end
