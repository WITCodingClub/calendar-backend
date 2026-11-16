# frozen_string_literal: true

require "rails_helper"

RSpec.describe OauthCredentials::Http do
  describe ".post_form" do
    it "posts the params as a form with both timeouts set" do
      request = stub_request(:post, "https://oauth.example.com/token")
                .with(body: { "grant_type" => "refresh_token" },
                      headers: { "Content-Type" => "application/x-www-form-urlencoded" })

      described_class.post_form("https://oauth.example.com/token", { grant_type: "refresh_token" })

      expect(request).to have_been_requested
      expect(described_class.connection.options).to have_attributes(open_timeout: described_class::OPEN_TIMEOUT,
                                                                     timeout: described_class::READ_TIMEOUT)
    end
  end

  describe ".parse" do
    it "reads a JSON object, and gives an empty Hash for a blank, broken, or non-object body" do
      expect(described_class.parse('{"error":"invalid_grant"}')).to eq("error" => "invalid_grant")
      expect(described_class.parse({ "a" => 1 })).to eq("a" => 1)
      expect(described_class.parse("")).to eq({})
      expect(described_class.parse("<html>")).to eq({})
      expect(described_class.parse("[1]")).to eq({})
    end
  end
end
