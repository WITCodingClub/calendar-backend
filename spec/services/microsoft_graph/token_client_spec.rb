# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftGraph::TokenClient, :microsoft_graph do
  subject(:token_client) { described_class.new }

  let(:redirect_uri) { "https://calendar.example.test/auth/microsoft_graph/callback" }

  describe "#authorize_url" do
    it "asks for the calendar scopes with a PKCE S256 challenge" do
      url   = URI(token_client.authorize_url(state: "signed-state", code_verifier: "verifier-123", redirect_uri: redirect_uri))
      query = URI.decode_www_form(url.query).to_h

      expect(url.host).to eq("login.microsoftonline.com")
      expect(url.path).to eq("/organizations/oauth2/v2.0/authorize")
      expect(query).to include(
        "client_id"             => "test-client-id",
        "response_type"         => "code",
        "redirect_uri"          => redirect_uri,
        "state"                 => "signed-state",
        "code_challenge"        => described_class.code_challenge("verifier-123"),
        "code_challenge_method" => "S256"
      )
      expect(query["scope"].split).to include("offline_access", "Calendars.ReadWrite", "MailboxSettings.ReadWrite")
    end
  end

  describe "#exchange_code" do
    it "trades the code for tokens and reads the account from the id token" do
      stub = stub_request(:post, MicrosoftGraphHelpers::TOKEN_URL)
             .with(body: hash_including("grant_type" => "authorization_code", "code" => "auth-code",
                                        "code_verifier" => "verifier-123", "client_secret" => "test-client-secret"))
             .to_return(graph_json_response("token_success"))

      token = token_client.exchange_code(code: "auth-code", code_verifier: "verifier-123", redirect_uri: redirect_uri)

      expect(stub).to have_been_requested
      expect(token.access_token).to eq("synthetic-access-token")
      expect(token.refresh_token).to eq("synthetic-refresh-token")
      expect(token.expires_at).to be_within(1.minute).of(1.hour.from_now)
      expect(token.claims).to include("oid" => "00000000-0000-0000-0000-000000000001", "email" => "student@example.edu")
    end

    it "raises with the error code but not the description" do
      stub_request(:post, MicrosoftGraphHelpers::TOKEN_URL).to_return(graph_json_response("token_invalid_grant", status: 400))

      expect { token_client.exchange_code(code: "spent", code_verifier: "v", redirect_uri: redirect_uri) }
        .to raise_error(MicrosoftGraph::AuthError) { |error|
          expect(error.message).to include("invalid_grant")
          expect(error.message).not_to include("Synthetic description")
          expect(error.status).to eq(400)
        }
    end
  end

  describe "#refresh!" do
    it "stores the new access token and the rotated refresh token" do
      credential = create(:oauth_credential, :microsoft, refresh_token: "old-refresh-token", token_expires_at: 1.minute.ago)
      stub_request(:post, MicrosoftGraphHelpers::TOKEN_URL)
        .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "old-refresh-token"))
        .to_return(graph_json_response("token_refresh"))

      token_client.refresh!(credential)

      expect(credential.reload).to have_attributes(
        access_token:  "synthetic-refreshed-access-token",
        refresh_token: "synthetic-rotated-refresh-token"
      )
      expect(credential.token_expires_at).to be_within(1.minute).of(1.hour.from_now)
    end

    it "uses the token that a refresh in another process got while it waited for the row" do
      credential = create(:oauth_credential, :microsoft, access_token: "old-access-token", token_expires_at: 1.minute.ago)
      OauthCredential.find(credential.id).update!(access_token: "token-from-the-other-refresh", token_expires_at: 1.hour.from_now)

      token_client.refresh!(credential)

      expect(a_request(:post, MicrosoftGraphHelpers::TOKEN_URL)).not_to have_been_made
      expect(credential.access_token).to eq("token-from-the-other-refresh")
      expect(credential.reload).not_to be_token_revoked
    end

    it "refuses a credential without a refresh token" do
      credential = create(:oauth_credential, :microsoft, refresh_token: nil)

      expect { token_client.refresh!(credential) }.to raise_error(MicrosoftGraph::AuthError)
      expect(credential.reload).not_to be_token_revoked
    end

    it "marks the credential revoked when Microsoft answers invalid_grant" do
      credential = create(:oauth_credential, :microsoft, token_expires_at: 1.minute.ago)
      stub_request(:post, MicrosoftGraphHelpers::TOKEN_URL).to_return(graph_json_response("token_invalid_grant", status: 400))

      expect { token_client.refresh!(credential) }.to raise_error(MicrosoftGraph::AuthError)
      expect(credential.reload).to be_token_revoked
    end
  end
end
