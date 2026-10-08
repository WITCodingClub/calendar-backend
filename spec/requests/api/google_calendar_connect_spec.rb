# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/user/gcal", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def state_from(oauth_url)
    state = Rack::Utils.parse_query(URI(oauth_url).query)["state"]
    GoogleOauthStateService.verify_state(state)
  end

  it "starts the flow without an email, so the person picks any account" do
    post "/api/user/gcal", headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("message" => "OAuth required", "email" => nil)
    expect(body["oauth_url"]).to start_with("http://www.example.com/auth/google_oauth2?state=")
    expect(state_from(body["oauth_url"])).to include("user_id" => user.id, "email" => nil)
  end

  it "keeps the old request shape: an email limits the flow to that account" do
    post "/api/user/gcal", params: { email: "new@example.com" }, headers: headers

    body = JSON.parse(response.body)
    expect(body).to include("message" => "OAuth required", "email" => "new@example.com")
    expect(state_from(body["oauth_url"])).to include("email" => "new@example.com")
  end

  it "reports an email that is already connected" do
    credential = create(:oauth_credential, user: user, email: "linked@example.com")
    service    = instance_double(GoogleCalendarService, create_or_get_course_calendar: "cal-1")
    allow(GoogleCalendarService).to receive(:new).with(user).and_return(service)

    post "/api/user/gcal", params: { email: credential.email }, headers: headers

    expect(JSON.parse(response.body)).to include("message" => "email already connected", "calendar_id" => "cal-1")
  end
end
