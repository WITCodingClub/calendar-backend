# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::ClientMetadataDocument do
  include ActiveSupport::Testing::TimeHelpers

  let(:url) { "https://client.example/oauth/metadata.json" }
  let(:document) do
    {
      "client_id"                  => url,
      "client_name"                => "Example Client",
      "redirect_uris"              => [ "https://client.example/cb", "http://localhost/callback" ],
      "token_endpoint_auth_method" => "none"
    }
  end
  let(:client) { instance_double(Oauth::MetadataDocumentClient, fetch: document) }

  def application(client_id = url) = described_class.new(client_id, client: client).application

  it "knows a metadata document client id" do
    expect(described_class.client_id?(url)).to be(true)
    expect(described_class.client_id?("abc123")).to be(false)
  end

  it "keeps the client as a public application with the URL as its uid" do
    app = application

    expect(app).to be_persisted
    expect(app).to have_attributes(uid: url, name: "Example Client", confidential: false, dynamic: true)
    expect(app.redirect_uri.split).to eq(document["redirect_uris"])
  end

  it "uses the kept copy for an hour, then fetches again" do
    application
    application
    expect(client).to have_received(:fetch).once

    travel(2.hours) do
      document["client_name"] = "Renamed"
      expect(application.name).to eq("Renamed")
    end
    expect(client).to have_received(:fetch).twice
  end

  it "refuses a document that names another client_id" do
    document["client_id"] = "https://evil.example/metadata.json"

    expect { application }.to raise_error(Oauth::InvalidClientMetadataError, /different client_id/)
  end

  it "refuses a document with a bad redirect URI or a secret" do
    document["redirect_uris"] = [ "http://evil.example/cb" ]
    expect { application }.to raise_error(Oauth::InvalidClientMetadataError, /must use https/)

    document["redirect_uris"] = [ "https://client.example/cb" ]
    document["token_endpoint_auth_method"] = "client_secret_basic"
    expect { application }.to raise_error(Oauth::InvalidClientMetadataError, /must be none/)
  end

  [
    "https://client.example",
    "https://client.example/",
    "https://client.example/a/../b",
    "https://user@client.example/m.json",
    "https://client.example/m.json#x",
    "https://client.example/#{'a' * 2_000}",
    "https://client example/m.json"
  ].each do |client_id|
    it "refuses the client id #{client_id.truncate(40)}" do
      expect { application(client_id) }.to raise_error(Oauth::InvalidClientMetadataError, /not a valid metadata document URL/)
    end
  end

  it "turns a fetch error into an invalid client" do
    allow(client).to receive(:fetch).and_raise(Oauth::MetadataDocumentClient::FetchError, "answered 404")

    expect { application }.to raise_error(Oauth::InvalidClientMetadataError, "answered 404")
  end

  it "finds the client that a parallel request saved first" do
    # The uniqueness check sees the other row. Without it, the unique index
    # raises RecordNotUnique, which takes the same path.
    winner = create(:oauth_application, uid: url)
    allow(Doorkeeper::Application).to receive(:find_by).and_return(nil)
    allow(Doorkeeper::Application).to receive(:find_by!).with(uid: url).and_return(winner)

    expect(application).to eq(winner)
  end

  it "finds the client when the unique index catches the race" do
    winner = create(:oauth_application, uid: url)
    allow(Doorkeeper::Application).to receive(:find_by).and_return(nil)
    allow(Doorkeeper::Application).to receive(:find_by!).with(uid: url).and_return(winner)
    allow_any_instance_of(Doorkeeper::Application).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique) # rubocop:disable RSpec/AnyInstance

    expect(application).to eq(winner)
  end
end
