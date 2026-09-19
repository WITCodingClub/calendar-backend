# frozen_string_literal: true

require "rails_helper"

# Google Calendar supports custom event colors, so the extension can save any
# "#rrggbb" color. Old extension versions still send a legacy color id.
RSpec.describe "Event preference colors", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:meeting_time) { create(:course_meeting_time) }
  let(:url) { "/api/meeting_times/#{meeting_time.public_id}/preference" }

  def json = JSON.parse(response.body)

  before do
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
  end

  it "saves a custom color and returns it as hex" do
    put url, params: { event_preference: { color_id: "#1A2B3C" } }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(json.dig("individual_preference", "color_id")).to eq("#1a2b3c")
    expect(json.dig("resolved", "color_id")).to eq("#1a2b3c")

    get url, headers: headers

    expect(json.dig("resolved", "color_id")).to eq("#1a2b3c")
  end

  it "turns a legacy color id into the hex of its palette color" do
    put url, params: { event_preference: { color_id: 7 } }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(json.dig("resolved", "color_id")).to eq(GoogleColors::PEACOCK)
  end

  it "rejects a value that is not a color" do
    put url, params: { event_preference: { color_id: "#1a2b3c; color: red" } }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "resolves a class without a color preference to the default hex color of its schedule type" do
    user.user_extension_config.update!(default_color_lecture: "#abcdef")

    get url, headers: headers

    expect(json.dig("resolved", "color_id")).to eq("#abcdef")
  end
end
