# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasskeyRedirectAllowlist do
  def allows?(uri) = described_class.allows?(uri)

  context "with nothing configured" do
    it "accepts our own extension's redirect shapes" do
      expect(allows?("https://aceelinogfcceklkpacakdeddnaakicj.chromiumapp.org/")).to be(true)
      expect(allows?("https://7145dcff.extensions.allizom.org/")).to be(true)
    end

    it "refuses anywhere else, so the page cannot carry a code off-site" do
      expect(allows?("https://evil.example.com/")).to be(false)
      expect(allows?("https://calendar.witcc.dev/")).to be(false)
    end

    it "refuses a lookalike host that merely contains the suffix" do
      expect(allows?("https://chromiumapp.org.evil.example/")).to be(false)
    end

    it "refuses plain http, which would expose the code in transit" do
      expect(allows?("http://abc.chromiumapp.org/")).to be(false)
    end

    it "refuses anything that is not a URL at all" do
      expect(allows?("")).to be(false)
      expect(allows?(nil)).to be(false)
      expect(allows?("javascript:alert(1)")).to be(false)
      expect(allows?("not a uri")).to be(false)
    end
  end

  context "with an explicit list" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("PASSKEY_REDIRECT_URIS")
        .and_return("https://known.chromiumapp.org/,https://other.extensions.allizom.org/")
    end

    it "accepts a listed address" do
      expect(allows?("https://known.chromiumapp.org/")).to be(true)
      expect(allows?("https://other.extensions.allizom.org/")).to be(true)
    end

    it "stops accepting the shapes it allowed by default" do
      expect(allows?("https://unlisted.chromiumapp.org/")).to be(false)
    end

    it "ignores a query string, which the browser may append" do
      expect(allows?("https://known.chromiumapp.org/?state=abc")).to be(true)
    end
  end
end
