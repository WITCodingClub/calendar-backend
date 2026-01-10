# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::Notifications DND", type: :request do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:headers) { { "Authorization" => "Bearer #{jwt_token}", "Content-Type" => "application/json" } }

  before do
    # Enable the v1 feature flag for API access
    Flipper.enable(FlipperFlags::V1, user)
  end

  describe "GET /api/user/notifications_status" do
    context "when notifications are enabled (default)" do
      it "returns notifications_disabled as false" do
        get "/api/user/notifications_status", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["notifications_disabled"]).to be false
        expect(json["notifications_disabled_until"]).to be_nil
      end
    end

    context "when notifications are disabled" do
      before do
        user.disable_notifications!
      end

      it "returns notifications_disabled as true with the disabled_until timestamp" do
        get "/api/user/notifications_status", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["notifications_disabled"]).to be true
        expect(json["notifications_disabled_until"]).to be_present
      end
    end

    context "when notifications were disabled but have expired" do
      before do
        user.update!(notifications_disabled_until: 1.hour.ago)
      end

      it "returns notifications_disabled as false" do
        get "/api/user/notifications_status", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["notifications_disabled"]).to be false
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        get "/api/user/notifications_status"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/user/notifications/disable" do
    context "without duration parameter" do
      it "disables notifications indefinitely" do
        post "/api/user/notifications/disable", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["notifications_disabled"]).to be true
        expect(json["notifications_disabled_until"]).to be_present
        expect(json["message"]).to eq("Notifications disabled")

        # Verify the user is actually in DND mode
        user.reload
        expect(user.notifications_disabled?).to be true
      end
    end

    context "with duration parameter" do
      it "disables notifications for the specified duration" do
        freeze_time do
          post "/api/user/notifications/disable",
               params: { duration: 3600 }.to_json, # 1 hour in seconds
               headers: headers

          expect(response).to have_http_status(:ok)
          json = response.parsed_body
          expect(json["notifications_disabled"]).to be true

          user.reload
          expect(user.notifications_disabled?).to be true
          expect(user.notifications_disabled_until).to be_within(1.second).of(1.hour.from_now)
        end
      end
    end

    context "with zero duration" do
      it "disables notifications indefinitely" do
        post "/api/user/notifications/disable",
             params: { duration: 0 }.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)
        user.reload
        expect(user.notifications_disabled?).to be true
        expect(user.notifications_disabled_until).to be > 50.years.from_now
      end
    end

    context "with negative duration" do
      it "returns bad request error" do
        post "/api/user/notifications/disable",
             params: { duration: -3600 }.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("Duration cannot be negative")

        # Verify notifications were NOT disabled
        user.reload
        expect(user.notifications_disabled?).to be false
      end
    end

    context "with excessively large duration" do
      it "returns bad request error for duration over 100 years" do
        post "/api/user/notifications/disable",
             params: { duration: 101.years.to_i }.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["error"]).to eq("Duration cannot exceed 100 years")

        # Verify notifications were NOT disabled
        user.reload
        expect(user.notifications_disabled?).to be false
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        post "/api/user/notifications/disable"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/user/notifications/enable" do
    context "when notifications are disabled" do
      before do
        user.disable_notifications!
      end

      it "re-enables notifications" do
        post "/api/user/notifications/enable", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["notifications_disabled"]).to be false
        expect(json["notifications_disabled_until"]).to be_nil
        expect(json["message"]).to eq("Notifications enabled")

        user.reload
        expect(user.notifications_disabled?).to be false
      end
    end

    context "when notifications are already enabled" do
      it "returns success (idempotent)" do
        post "/api/user/notifications/enable", headers: headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["notifications_disabled"]).to be false
      end
    end

    context "without authentication" do
      it "returns unauthorized" do
        post "/api/user/notifications/enable"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "integration: DND affects PreferenceResolver" do
    let(:term) { create(:term) }
    let(:course) { create(:course, schedule_type: "lecture", term: term) }
    let(:building) { create(:building) }
    let(:room) { create(:room, building: building) }
    let!(:meeting_time) { create(:meeting_time, course: course, room: room) }
    let!(:enrollment) { create(:enrollment, user: user, course: course, term: term) }

    before do
      # Set up a global preference with reminders
      create(:calendar_preference,
             user: user,
             scope: :global,
             reminder_settings: [{ "time" => "30", "type" => "minutes", "method" => "popup" }])
    end

    it "disabling notifications causes PreferenceResolver to return empty reminder_settings" do
      # Verify reminders exist before DND
      resolver_before = PreferenceResolver.new(user)
      prefs_before = resolver_before.resolve_for(meeting_time)
      expect(prefs_before[:reminder_settings]).not_to be_empty

      # Disable notifications
      post "/api/user/notifications/disable", headers: headers
      expect(response).to have_http_status(:ok)

      # Verify reminders are now empty due to DND
      user.reload
      resolver_after = PreferenceResolver.new(user)
      prefs_after = resolver_after.resolve_for(meeting_time)
      expect(prefs_after[:reminder_settings]).to eq([])
    end

    it "re-enabling notifications restores normal PreferenceResolver behavior" do
      # Disable notifications first
      user.disable_notifications!

      # Verify DND is active
      resolver_dnd = PreferenceResolver.new(user)
      prefs_dnd = resolver_dnd.resolve_for(meeting_time)
      expect(prefs_dnd[:reminder_settings]).to eq([])

      # Re-enable notifications
      post "/api/user/notifications/enable", headers: headers
      expect(response).to have_http_status(:ok)

      # Verify reminders are back to normal
      user.reload
      resolver_enabled = PreferenceResolver.new(user)
      prefs_enabled = resolver_enabled.resolve_for(meeting_time)
      expect(prefs_enabled[:reminder_settings]).to eq([{ "time" => "30", "type" => "minutes", "method" => "popup" }])
    end
  end
end
