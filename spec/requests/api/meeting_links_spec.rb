# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::MeetingLinks", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)    { Time.zone }
  let(:user)    { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:params)  { { title: "Project check-in", starts_on: "2026-10-08", ends_on: "2026-10-16", duration_minutes: 30 } }

  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  after { Flipper.disable(FlipperFlags::MEETING_LINKS) }

  it "answers 401 without a token" do
    get "/api/meeting_links"

    expect(response).to have_http_status(:unauthorized)
  end

  it "answers 404 while the flag is off, and makes nothing" do
    post "/api/meeting_links", params: params, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error" => "Meeting links are not enabled", "code" => "NOT_FOUND")
    expect(MeetingLink.count).to eq(0)
  end

  context "when the flag is on for the person" do
    before { Flipper.enable_actor(FlipperFlags::MEETING_LINKS, user) }

    describe "POST /api/meeting_links" do
      it "makes a link and returns its URL once" do
        post "/api/meeting_links", params: params.merge(expires_at: "2026-10-12T17:00:00-04:00"), headers: headers, as: :json

        link = MeetingLink.sole
        body = response.parsed_body["meeting_link"]
        expect(response).to have_http_status(:created)
        expect(body).to eq(
          "id"               => link.public_id,
          "title"            => "Project check-in",
          "starts_on"        => "2026-10-08",
          "ends_on"          => "2026-10-16",
          "duration_minutes" => 30,
          "expires_at"       => "2026-10-12T17:00:00-04:00",
          "status"           => "active",
          "created_at"       => link.created_at.iso8601,
          "booking"          => nil,
          "url"              => body["url"]
        )
        token = URI(body["url"]).path.delete_prefix("/meet/")
        expect(MeetingLink.find_by_token(token)).to eq(link)
        expect(link.token_digest).not_to eq(token)
      end

      it "expires at the end of the last day when no expiry is given" do
        post "/api/meeting_links", params: params, headers: headers, as: :json

        expect(response.parsed_body.dig("meeting_link", "expires_at")).to eq("2026-10-16T23:59:59-04:00")
      end

      it "answers 422 with the reason for a link that is not valid" do
        post "/api/meeting_links", params: params.merge(duration_minutes: 25), headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("Duration minutes is not included in the list")
      end

      it "answers 400 for a missing field or a bad date" do
        post "/api/meeting_links", params: params.except(:ends_on), headers: headers, as: :json
        expect(response).to have_http_status(:bad_request)

        post "/api/meeting_links", params: params.merge(starts_on: "next week"), headers: headers, as: :json
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["error"]).to eq("starts_on must be an ISO 8601 date")

        post "/api/meeting_links", params: params.merge(expires_at: "2026-10-12T17:00:00"), headers: headers, as: :json
        expect(response).to have_http_status(:bad_request)
      end
    end

    describe "GET /api/meeting_links" do
      it "lists only the person's links, newest first, with no URL, and with the booking of a used link" do
        older  = create(:meeting_link, user: user, created_at: 2.days.ago)
        used   = create(:meeting_link, :used, user: user, created_at: 1.day.ago)
        create(:meeting_link)

        get "/api/meeting_links", headers: headers

        links = response.parsed_body["meeting_links"]
        expect(links.pluck("id")).to eq([ used.public_id, older.public_id ])
        expect(links).to all(satisfy { |link| !link.key?("url") })
        expect(links.first["status"]).to eq("used")
        expect(links.first["booking"]).to eq(
          "meeting_id"  => used.friend_meeting.public_id,
          "start_time"  => used.friend_meeting.start_time.iso8601,
          "end_time"    => used.friend_meeting.end_time.iso8601,
          "guest_name"  => "Sample Guest",
          "guest_email" => used.friend_meeting.guest_email
        )
      end
    end

    describe "DELETE /api/meeting_links/:id" do
      it "revokes the person's link" do
        link = create(:meeting_link, user: user)

        delete "/api/meeting_links/#{link.public_id}", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("meeting_link", "status")).to eq("revoked")
        expect(link.reload).to be_revoked
      end

      it "keeps a used link as used" do
        link = create(:meeting_link, :used, user: user)

        delete "/api/meeting_links/#{link.public_id}", headers: headers

        expect(response.parsed_body.dig("meeting_link", "status")).to eq("used")
        expect(link.reload).not_to be_revoked
      end

      it "answers 404 for another person's link, and leaves it alone" do
        link = create(:meeting_link)

        delete "/api/meeting_links/#{link.public_id}", headers: headers

        expect(response).to have_http_status(:not_found)
        expect(link.reload).not_to be_revoked
      end
    end
  end
end
