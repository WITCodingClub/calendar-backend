# frozen_string_literal: true

require "rails_helper"

RSpec.describe Risc::TokenMatcher do
  let(:refresh_token) { "1//synthetic-refresh-token-matcher" }
  let!(:credential) { create(:oauth_credential, refresh_token: refresh_token) }
  let(:raw_digest) { Digest::SHA512.digest(Digest::SHA512.digest(refresh_token)) }

  def ids(algorithm, token)
    described_class.new(algorithm:, token:).matching_ids(OauthCredential.google)
  end

  it "matches the standard base64 of a double SHA-512" do
    expect(ids("hash_base64_sha512_sha512", Base64.strict_encode64(raw_digest))).to eq([ credential.id ])
  end

  # Google names base64 but not the alphabet or the padding.
  it "matches the URL-safe base64 alphabet, with or without padding" do
    expect(ids("hash_base64_sha512_sha512", Base64.urlsafe_encode64(raw_digest, padding: false))).to eq([ credential.id ])
  end

  # Google does not say whether the inner digest is raw bytes or hex.
  it "matches a double SHA-512 whose inner digest is hex" do
    digest = Base64.strict_encode64(Digest::SHA512.digest(Digest::SHA512.hexdigest(refresh_token)))

    expect(ids("hash_base64_sha512_sha512", digest)).to eq([ credential.id ])
  end

  it "matches nothing for an identifier that is not a base64 SHA-512" do
    expect(ids("hash_base64_sha512_sha512", "not*base64")).to eq([])
    expect(ids("hash_base64_sha512_sha512", Base64.strict_encode64("short"))).to eq([])
  end

  it "matches a prefix of exactly 16 characters only" do
    expect(ids("prefix", refresh_token.first(16))).to eq([ credential.id ])
    expect(ids("prefix", refresh_token.first(8))).to eq([])
  end

  it "skips a credential with no refresh token" do
    create(:oauth_credential, email: "no-refresh@example.test")

    expect(ids("prefix", refresh_token.first(16))).to eq([ credential.id ])
  end

  it "rejects an identifier that Google does not document" do
    expect { described_class.new(algorithm: "plain", token: refresh_token) }.to raise_error(ArgumentError)
  end
end
