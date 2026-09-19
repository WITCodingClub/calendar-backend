# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::ConnectedAccounts", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  after { Flipper.disable(FlipperFlags::MICROSOFT_GRAPH_CALENDAR) }

  def disconnect_path_for(credential)
    get dashboard_connected_accounts_path
    form = Nokogiri::HTML(response.body).at_css("form[action*='/dashboard/connected_accounts/'][action*='#{credential.public_id}']")
    form["action"]
  end

  describe "DELETE /dashboard/connected_accounts/:id" do
    it "disconnects a Google credential and redirects with the success notice" do
      credential = create(:oauth_credential, user: user)
      create(:oauth_credential, user: user, email: Faker::Internet.email)

      delete disconnect_path_for(credential)

      expect(response).to redirect_to(dashboard_connected_accounts_path)
      follow_redirect!
      expect(response.body).to include("Account disconnected.")
      expect(OauthCredential.exists?(credential.id)).to be(false)
    end

    it "does not remove a credential that belongs to another user" do
      create(:oauth_credential, user: user)
      other_credential = create(:oauth_credential, user: create(:user))

      delete dashboard_connected_account_path(other_credential.public_id)

      expect(response).to redirect_to(dashboard_connected_accounts_path)
      follow_redirect!
      expect(response.body).to include("Credential not found.")
      expect(OauthCredential.exists?(other_credential.id)).to be(true)
    end
  end

  def outlook_section
    Nokogiri::HTML(response.body).at_css("#outlook-calendar")
  end

  describe "GET /dashboard/connected_accounts" do
    # The Google account that the person onboarded with.
    before { create(:oauth_credential, user: user) }

    context "when the Microsoft Graph provider is off" do
      it "does not show the Outlook section" do
        get dashboard_connected_accounts_path

        expect(response).to have_http_status(:ok)
        expect(outlook_section).to be_nil
        expect(response.body).not_to include("Connect Outlook")
      end

      it "does not show the Outlook section when only the flag is on", :microsoft_graph do
        Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user)

        with_microsoft_client_unset { get dashboard_connected_accounts_path }

        expect(outlook_section).to be_nil
      end
    end

    context "when the Microsoft Graph provider is on", :microsoft_graph do
      before { Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user) }

      it "links to the Microsoft sign-in with a signed state" do
        get dashboard_connected_accounts_path

        link = outlook_section.at_css("a", text: "Connect Outlook")
        uri  = URI(link["href"])
        expect(uri.path).to eq("/auth/microsoft_graph")
        state = URI.decode_www_form(uri.query).to_h.fetch("state")
        expect(MicrosoftGraph::OauthState.verify(state)).to include("user_id" => user.id)
      end

      it "shows a syncing calendar with a disconnect button" do
        credential = create(:oauth_credential, :microsoft, user: user)
        create(:course_calendar, :microsoft, oauth_credential: credential)

        get dashboard_connected_accounts_path

        expect(outlook_section.text).to include(credential.email, "Syncing")
        expect(outlook_section.text).not_to include("Connect Outlook", "Reconnect")
        expect(outlook_section.at_css("form[action='#{dashboard_connected_account_path(credential.public_id)}']")).to be_present
      end

      it "offers to show classes as busy for a separate calendar" do
        credential = create(:oauth_credential, :microsoft, user: user)
        create(:course_calendar, :microsoft, oauth_credential: credential)

        get dashboard_connected_accounts_path

        form = outlook_section.at_css("form[action='#{calendar_placement_dashboard_connected_account_path(credential.public_id)}']")
        expect(outlook_section.text).to include("do not show as busy", "Show classes as busy")
        expect(form.at_css("input[name='placement']")["value"]).to eq("primary")
      end

      it "offers a separate calendar when classes are in the main calendar" do
        credential = create(:oauth_credential, :microsoft, user: user)
        create(:course_calendar, :primary, oauth_credential: credential)

        get dashboard_connected_accounts_path

        form = outlook_section.at_css("form[action='#{calendar_placement_dashboard_connected_account_path(credential.public_id)}']")
        expect(outlook_section.text).to include("show as busy", "Use a separate calendar")
        expect(form.at_css("input[name='placement']")["value"]).to eq("separate")
      end

      it "shows a sign-in that expired" do
        create(:oauth_credential, :microsoft, user: user, refresh_token: nil)

        get dashboard_connected_accounts_path

        expect(outlook_section.text).to include("Sign-in expired", "Reconnect")
      end

      it "shows access that Microsoft revoked" do
        create(:oauth_credential, :microsoft, user: user, metadata: { "token_revoked" => true })

        get dashboard_connected_accounts_path

        expect(outlook_section.text).to include("Access revoked", "Reconnect")
      end

      it "shows a connection that has no calendar" do
        create(:oauth_credential, :microsoft, user: user)

        get dashboard_connected_accounts_path

        expect(outlook_section.text).to include("No calendar")
      end

      it "keeps Microsoft accounts out of the Google list" do
        credential = create(:oauth_credential, :microsoft, user: user, email: Faker::Internet.email)

        get dashboard_connected_accounts_path

        google_list = response.body.split('id="outlook-calendar"').first
        expect(google_list).not_to include(credential.email)
      end
    end
  end

  describe "PATCH /dashboard/connected_accounts/:id/calendar_placement", :microsoft_graph do
    include ActiveJob::TestHelper

    let(:credential) { create(:oauth_credential, :microsoft, user: user) }

    before { Flipper.enable_actor(FlipperFlags::MICROSOFT_GRAPH_CALENDAR, user) }

    it "starts the move" do
      expect { patch calendar_placement_dashboard_connected_account_path(credential.public_id), params: { placement: "primary" } }
        .to have_enqueued_job(MicrosoftGraphCalendarPlacementJob).with(user, "primary")

      expect(response).to redirect_to(dashboard_connected_accounts_path)
      expect(flash[:notice]).to include("moving")
    end

    it "refuses a placement it does not know" do
      expect { patch calendar_placement_dashboard_connected_account_path(credential.public_id), params: { placement: "shared" } }
        .not_to have_enqueued_job(MicrosoftGraphCalendarPlacementJob)

      expect(flash[:alert]).to be_present
    end

    it "refuses the account of a different person" do
      other = create(:oauth_credential, :microsoft)

      expect { patch calendar_placement_dashboard_connected_account_path(other.public_id), params: { placement: "primary" } }
        .not_to have_enqueued_job(MicrosoftGraphCalendarPlacementJob)

      expect(flash[:alert]).to eq("Credential not found.")
    end

    it "refuses a Google account" do
      google = user.oauth_credentials.google.first

      expect { patch calendar_placement_dashboard_connected_account_path(google.public_id), params: { placement: "primary" } }
        .not_to have_enqueued_job(MicrosoftGraphCalendarPlacementJob)
    end

    it "refuses while the provider is off" do
      Flipper.disable(FlipperFlags::MICROSOFT_GRAPH_CALENDAR)

      expect { patch calendar_placement_dashboard_connected_account_path(credential.public_id), params: { placement: "primary" } }
        .not_to have_enqueued_job(MicrosoftGraphCalendarPlacementJob)
    end
  end

  describe "DELETE /dashboard/connected_accounts/:id", :microsoft_graph do
    # The Google account that the person onboarded with. Without a second
    # account, the dashboard refuses the disconnect.
    before { create(:oauth_credential, user: user) }

    it "removes the Outlook calendar and then the Microsoft account" do
      credential = create(:oauth_credential, :microsoft, user: user)
      create(:course_calendar, :microsoft, oauth_credential: credential, external_calendar_id: "AAMkSyntheticCalendar1")
      delete_calendar = stub_request(:delete, "#{MicrosoftGraphHelpers::GRAPH_URL}/me/calendars/AAMkSyntheticCalendar1")
                        .to_return(status: 204)

      delete dashboard_connected_account_path(credential.public_id)

      expect(response).to redirect_to(dashboard_connected_accounts_path)
      expect(flash[:notice]).to eq("Account disconnected.")
      expect(delete_calendar).to have_been_requested
      expect(user.oauth_credentials.microsoft).to be_empty
    end

    it "disconnects the account when Graph cannot delete the calendar" do
      credential = create(:oauth_credential, :microsoft, user: user)
      create(:course_calendar, :microsoft, oauth_credential: credential, external_calendar_id: "AAMkSyntheticCalendar1")
      stub_request(:delete, "#{MicrosoftGraphHelpers::GRAPH_URL}/me/calendars/AAMkSyntheticCalendar1")
        .to_return(graph_json_response("error_unauthorized", status: 500))

      delete dashboard_connected_account_path(credential.public_id)

      expect(flash[:notice]).to eq("Account disconnected.")
      expect(user.oauth_credentials.microsoft).to be_empty
    end
  end

  def with_microsoft_client_unset
    original = MicrosoftGraphHelpers::CONFIGURED_ENV.keys.index_with { |key| ENV.delete(key) }
    yield
  ensure
    original.each { |key, value| ENV[key] = value if value }
  end
end
