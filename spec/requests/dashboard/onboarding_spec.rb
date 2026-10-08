# frozen_string_literal: true

require "rails_helper"

# A user who has not processed any courses sees the onboarding page instead
# of an empty dashboard (#644). Account pages still work for that user.
RSpec.describe "Dashboard onboarding gate", type: :request do
  let(:new_user) { create(:user) }

  describe "for a user with no processed courses" do
    before { sign_in new_user }

    it "sends the dashboard home to the onboarding page" do
      get dashboard_root_path

      expect(response).to redirect_to(dashboard_onboarding_path)
    end

    {
      "the schedule"         => -> { dashboard_schedule_path },
      "calendar preferences" => -> { dashboard_calendar_preferences_path },
      "the ICS feed"         => -> { dashboard_ics_feed_path },
      "friends"              => -> { dashboard_friends_path }
    }.each do |name, path|
      it "sends #{name} to the onboarding page" do
        get instance_exec(&path)

        expect(response).to redirect_to(dashboard_onboarding_path)
      end
    end

    it "does not let the user change gated settings" do
      patch university_events_dashboard_calendar_preferences_path, params: { enabled: "1" }

      expect(response).to redirect_to(dashboard_onboarding_path)
    end

    it "shows the onboarding steps with the extension install link" do
      get dashboard_onboarding_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Install the extension")
      expect(response.body).to include(%(href="#{Rails.configuration.x.extension_install_url}"))
      expect(response.body).to include(new_user.email)
    end

    {
      "settings"           => -> { dashboard_settings_path },
      "connected accounts" => -> { dashboard_connected_accounts_path },
      "notifications"      => -> { dashboard_notifications_path }
    }.each do |name, path|
      it "still shows #{name}" do
        get instance_exec(&path)

        expect(response).to have_http_status(:ok)
      end
    end

    it "keeps the flash message across the redirect to the onboarding page" do
      get "/admin"
      follow_redirect!

      expect(response).to redirect_to(dashboard_onboarding_path)
      follow_redirect!
      expect(response.body).to include("You don&#39;t have permission to access that page.")
    end

    describe "friend requests" do
      # FriendshipMailer links to the requests page, so a new user must be
      # able to answer a request from the email.
      let(:requester) { create(:user, first_name: "Riley") }
      let!(:request) { create(:friendship, requester: requester, addressee: new_user) }

      it "still shows the friend requests page" do
        get requests_dashboard_friends_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(requester.email)
      end

      it "lets the user accept a request and returns to the requests page" do
        post accept_dashboard_friend_path(request.id)

        expect(request.reload).to be_accepted
        expect(response).to redirect_to(requests_dashboard_friends_path)
        follow_redirect!
        expect(response.body).to include("Riley added as a friend.")
      end

      it "lets the user decline a request and returns to the requests page" do
        post decline_dashboard_friend_path(request.id)

        expect(Friendship.exists?(request.id)).to be(false)
        expect(response).to redirect_to(requests_dashboard_friends_path)
      end

      it "shows the pending requests on the onboarding page" do
        get dashboard_onboarding_path

        expect(response.body).to include("You have 1 friend request.")
        expect(response.body).to include(%(href="#{requests_dashboard_friends_path}"))
      end

      it "does not show a friend request card when no request is pending" do
        request.accepted!

        get dashboard_onboarding_path

        expect(response.body).not_to include("friend request")
      end

      it "still sends a friend's schedule to the onboarding page" do
        request.accepted!

        get dashboard_friend_path(requester.public_id)

        expect(response).to redirect_to(dashboard_onboarding_path)
      end
    end

    it "still lets the user remove a Microsoft sign-in" do
      identity = create(:sign_in_identity, user: new_user)

      expect { delete dashboard_sign_in_identity_path(identity) }.to change(SignInIdentity, :count).by(-1)
    end

    it "still lets the user sign out" do
      delete destroy_user_session_path

      get dashboard_settings_path
      expect(URI(response.location).path).to eq(new_user_session_path)
    end
  end

  describe "for a user with processed courses" do
    let(:user) { create(:user, :with_processed_courses) }

    before { sign_in user }

    it "shows the dashboard home" do
      get dashboard_root_path

      expect(response).to have_http_status(:ok)
    end

    it "sends the onboarding page back to the dashboard home" do
      get dashboard_onboarding_path

      expect(response).to redirect_to(dashboard_root_path)
    end

    it "still returns to the friends page after it accepts a request" do
      request = create(:friendship, requester: create(:user), addressee: user)

      post accept_dashboard_friend_path(request.id)

      expect(response).to redirect_to(dashboard_friends_path)
    end
  end

  describe "for an admin with no processed courses" do
    before { sign_in create(:user, :admin) }

    it "shows the dashboard home" do
      get dashboard_root_path

      expect(response).to have_http_status(:ok)
    end

    it "shows the schedule" do
      get dashboard_schedule_path

      expect(response).to have_http_status(:ok)
    end
  end
end
