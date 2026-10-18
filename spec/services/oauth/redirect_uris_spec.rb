# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::RedirectUris do
  describe ".error_for" do
    it "accepts HTTPS and loopback HTTP" do
      expect(described_class.error_for(%w[https://claude.ai/cb http://localhost:3000/cb http://127.0.0.1/cb])).to be_nil
    end

    it "refuses a list that is empty or not a list" do
      expect(described_class.error_for([])).to include("non-empty array")
      expect(described_class.error_for("https://claude.ai/cb")).to include("non-empty array")
    end

    it "refuses too many URIs" do
      uris = Array.new(described_class::MAX_COUNT + 1) { |i| "https://example.com/#{i}" }

      expect(described_class.error_for(uris)).to include("too many")
    end

    {
      "a value that is not a string" => [ 42, "must be a string" ],
      "a URI that is too long"       => [ "https://example.com/#{'a' * 2_000}", "too long" ],
      "a relative URI"               => [ "/callback", "must be absolute" ],
      "a fragment"                   => [ "https://example.com/cb#x", "fragment" ],
      "user info"                    => [ "https://user:pass@example.com/cb", "user info" ],
      "HTTP on a public host"        => [ "http://example.com/cb", "must use https" ],
      "a custom scheme"              => [ "myapp://callback", "must use https" ],
      "a URI that does not parse"    => [ "https://exa mple.com", "not a valid URI" ]
    }.each do |label, (value, message)|
      it "refuses #{label}" do
        expect(described_class.error_for([ value ])).to include(message)
      end
    end
  end

  describe ".hosts" do
    it "lists each host once and skips a URI that does not parse" do
      expect(described_class.hosts("https://a.example/1\nhttps://a.example/2\nhttps://[bad")).to eq([ "a.example" ])
    end
  end
end
