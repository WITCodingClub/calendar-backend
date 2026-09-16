# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::ConnectedAccounts", type: :request do
  let(:user) { create(:user) }

  before do
    create(:oauth_credential, user: user)
    sign_in user
  end

  after { Flipper.disable(FlipperFlags::MICROSOFT_GRAPH_CALENDAR) }

  def outlook_section
    Nokogiri::HTML(response.body).at_css("#outlook-calendar")
  end

  describe "GET /dashboard/connected_accounts" do
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

  describe "DELETE /dashboard/connected_accounts/:id", :microsoft_graph do
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
