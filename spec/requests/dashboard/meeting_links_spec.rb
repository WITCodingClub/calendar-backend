# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::MeetingLinks", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { Time.zone }
  let(:user) { create(:user, :with_processed_courses) }
  let(:form) { { title: "Project check-in", starts_on: "2026-10-08", ends_on: "2026-10-16", duration_minutes: "30", expires_on: "2026-10-12" } }

  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  before { sign_in user }

  after { Flipper.disable(FeatureFlags::MEETING_LINKS) }

  it "answers 404 while the flag is off" do
    get dashboard_meeting_links_path
    expect(response).to have_http_status(:not_found)

    post dashboard_meeting_links_path, params: { meeting_link: form }
    expect(response).to have_http_status(:not_found)
    expect(MeetingLink.count).to eq(0)
  end

  it "shows no meeting links card on the friends page while the flag is off" do
    get dashboard_friends_path

    expect(response.body).not_to include(dashboard_meeting_links_path)
  end

  context "when the flag is on for the person" do
    before { Flipper.enable_actor(FeatureFlags::MEETING_LINKS, user) }

    it "links to the page from the friends page" do
      get dashboard_friends_path

      expect(response.body).to include(dashboard_meeting_links_path)
    end

    it "makes a link and shows its URL on the next page view only" do
      post dashboard_meeting_links_path, params: { meeting_link: form }

      link = MeetingLink.sole
      expect(link).to have_attributes(title: "Project check-in", duration_minutes: 30, starts_on: Date.new(2026, 10, 8))
      expect(link.expires_at).to be_within(1.second).of(zone.local(2026, 10, 12).end_of_day)
      expect(response).to redirect_to(dashboard_meeting_links_path)

      follow_redirect!
      url = response.body[%r{http://example\.com/meet/[\w-]+}]
      expect(MeetingLink.find_by_token(url.delete_prefix("http://example.com/meet/"))).to eq(link)

      get dashboard_meeting_links_path
      expect(response.body).not_to include("/meet/")
    end

    it "shows the reason when the link is not valid" do
      post dashboard_meeting_links_path, params: { meeting_link: form.merge(ends_on: "2026-10-01") }

      expect(MeetingLink.count).to eq(0)
      expect(flash[:alert]).to eq("Ends on must be on or after the start date")
    end

    it "lists the person's links with the booking, and not other people's links" do
      used  = create(:meeting_link, :used, user: user, title: "Booked link")
      other = create(:meeting_link, title: "Someone else's link")

      get dashboard_meeting_links_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Booked link").and include("Booked by Sample Guest (#{used.friend_meeting.guest_email})")
      expect(response.body).not_to include(other.title)
    end

    it "revokes an active link" do
      link = create(:meeting_link, user: user)

      delete dashboard_meeting_link_path(link.public_id)

      expect(link.reload).to be_revoked
      expect(flash[:notice]).to eq("Link revoked.")
    end

    it "does not revoke a used link" do
      link = create(:meeting_link, :used, user: user)

      delete dashboard_meeting_link_path(link.public_id)

      expect(link.reload).not_to be_revoked
      expect(flash[:alert]).to include("already used")
    end

    it "does not find another person's link" do
      link = create(:meeting_link)

      delete dashboard_meeting_link_path(link.public_id)

      expect(link.reload).not_to be_revoked
      expect(flash[:alert]).to eq("Link not found.")
    end
  end
end
