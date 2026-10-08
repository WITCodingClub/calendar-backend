# frozen_string_literal: true

require "rails_helper"

# Every API error has the same body: { "error": message, "code": CODE }.
# Api::ErrorRendering builds it, so a controller calls render_error and never
# writes the error hash itself.
RSpec.describe "API error format" do
  let(:user) { create(:user) }

  describe "Api::ErrorRendering.code_for" do
    it "uses the reason phrase of the status" do
      expect(Api::ErrorRendering.code_for(:bad_request)).to eq("BAD_REQUEST")
      expect(Api::ErrorRendering.code_for(:not_found)).to eq("NOT_FOUND")
      expect(Api::ErrorRendering.code_for(:forbidden)).to eq("FORBIDDEN")
    end

    it "uses the documented codes where they differ from the reason phrase" do
      expect(Api::ErrorRendering.code_for(:unprocessable_content)).to eq("VALIDATION_FAILED")
      expect(Api::ErrorRendering.code_for(:unprocessable_entity)).to eq("VALIDATION_FAILED")
      expect(Api::ErrorRendering.code_for(:too_many_requests)).to eq("RATE_LIMITED")
      expect(Api::ErrorRendering.code_for(:internal_server_error)).to eq("INTERNAL_ERROR")
    end
  end

  it "answers an unknown path with NOT_FOUND" do
    get "/api/not-a-route", headers: auth_headers_for(user)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error" => "Not found", "code" => "NOT_FOUND")
  end

  it "answers a missing parameter with BAD_REQUEST" do
    post "/api/process_courses/batch", params: {}, headers: auth_headers_for(user), as: :json

    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.keys).to contain_exactly("error", "code")
    expect(response.parsed_body["code"]).to eq("BAD_REQUEST")
  end

  it "keeps a code that the action sets" do
    stranger = create(:user)

    get "/api/friends/#{stranger.public_id}/busy_blocks", headers: auth_headers_for(user)

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["code"]).to eq("NOT_FRIENDS")
  end

  it "has no error hash written by hand in an API controller" do
    sources = Rails.root.glob("app/controllers/api/**/*.rb").reject { |path| path.basename.to_s == "graphql_controller.rb" }
    offenders = sources.select { |path| path.read.match?(/render\s*\(?\s*json:\s*\{[^}]*\berrors?:/m) }

    expect(offenders.map { |path| path.relative_path_from(Rails.root).to_s }).to be_empty
  end
end
