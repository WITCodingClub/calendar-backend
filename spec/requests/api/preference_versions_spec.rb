# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /api/user/preferences/version", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def json = JSON.parse(response.body)

  it "returns only the signed-in user's opaque token and prohibits response caching" do
    create(:event_preference, user: user, title_template: "Private title")
    expected_version = Preferences::Version.for(user)

    get "/api/user/preferences/version", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(json).to eq("version" => expected_version)
    expect(json["version"]).to match(/\A[0-9a-f]{64}\z/)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")

    get "/api/user/preferences/version", headers: headers

    expect(response).to have_http_status(:ok)
    expect(json["version"]).to eq(expected_version)
  end

  it "reflects persisted preference changes on the next request" do
    preference = create(:calendar_preference, user: user, title_template: "Original")

    get "/api/user/preferences/version", headers: headers
    expect(response).to have_http_status(:ok)
    version = json.fetch("version")

    preference.update_columns(title_template: "Changed")

    get "/api/user/preferences/version", headers: headers

    expect(response).to have_http_status(:ok)
    expect(json.fetch("version")).not_to eq(version)
  end

  it "does not accept a different account through request parameters" do
    other_user = create(:user)
    create(:event_preference, user: other_user, title_template: "Other user's title")

    get "/api/user/preferences/version", params: { user_id: other_user.id }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(json).to eq("version" => Preferences::Version.for(user))
    expect(json["version"]).not_to eq(Preferences::Version.for(other_user))
  end

  it "requires authentication" do
    get "/api/user/preferences/version"

    expect(response).to have_http_status(:unauthorized)
    expect(json["code"]).to eq("AUTH_MISSING")
    expect(json).not_to have_key("version")
  end

  it "rejects a revoked session" do
    token = api_token_for(user)
    UserSession.find_by!(jti: JsonWebTokenService.decode(token)[:jti]).revoke!

    get "/api/user/preferences/version", headers: { "Authorization" => "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
    expect(json["code"]).to eq("AUTH_REVOKED")
    expect(json).not_to have_key("version")
  end

  it "does not resolve templates or enqueue calendar sync work" do
    create(:event_preference, user: user, title_template: "Saved title")
    request_headers = headers
    expect(Preferences::Resolver).not_to receive(:new)
    expect(Preferences::TemplateRenderer).not_to receive(:new)
    expect(CourseCalendars::SyncJob).not_to receive(:perform_later)

    get "/api/user/preferences/version", headers: request_headers

    expect(response).to have_http_status(:ok)
  end
end
