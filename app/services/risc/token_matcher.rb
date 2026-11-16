# frozen_string_literal: true

require "digest"

module Risc
  # Finds the Google credentials whose refresh token a RISC token-revoked event
  # names. Google sends an identifier of the token, not the token
  # (https://developers.google.com/identity/protocols/risc, "OAuth token
  # identifiers"):
  #
  # - `prefix`: the first 16 characters of the token.
  # - `hash_base64_sha512_sha512`: "the double hash of the token using SHA-512",
  #   in base64.
  #
  # Google does not say which base64 alphabet it uses, or whether the inner
  # digest is raw bytes or hex. The matcher decodes either alphabet, with or
  # without padding, and compares the 64 bytes with both inner forms. A false
  # match needs a SHA-512 collision, so the extra forms add no risk.
  #
  # Refresh tokens are encrypted with Active Record encryption, so the database
  # cannot compare them. The matcher decrypts each candidate in Ruby, in
  # batches, and loads only the id and the token. Without a user, that is every
  # Google credential with a refresh token: a few thousand rows cost one
  # decryption and two SHA-512 digests each, well under a second.
  class TokenMatcher
    PREFIX = "prefix"
    DOUBLE_SHA512 = "hash_base64_sha512_sha512"
    ALGORITHMS = [ PREFIX, DOUBLE_SHA512 ].freeze
    PREFIX_LENGTH = 16
    BATCH_SIZE = 500

    def self.supported?(algorithm)
      ALGORITHMS.include?(algorithm)
    end

    def initialize(algorithm:, token:)
      raise ArgumentError, "unsupported token identifier" unless self.class.supported?(algorithm)

      @algorithm = algorithm
      @token = token.to_s
      @digest = decode_digest if algorithm == DOUBLE_SHA512
    end

    # The ids of the credentials in `scope` whose refresh token matches.
    def matching_ids(scope)
      return [] if @token.empty? || (@algorithm == DOUBLE_SHA512 && @digest.nil?)

      ids = []
      scope.where.not(refresh_token: nil).select(:id, :refresh_token).find_each(batch_size: BATCH_SIZE) do |credential|
        ids << credential.id if match?(credential.refresh_token.to_s)
      end
      ids
    end

    private

    def match?(refresh_token)
      return false if refresh_token.empty?

      case @algorithm
      when PREFIX
        @token.length == PREFIX_LENGTH &&
          ActiveSupport::SecurityUtils.secure_compare(refresh_token[0, PREFIX_LENGTH], @token)
      when DOUBLE_SHA512
        double_sha512_forms(refresh_token).any? { |form| ActiveSupport::SecurityUtils.secure_compare(form, @digest) }
      end
    end

    def double_sha512_forms(refresh_token)
      [
        Digest::SHA512.digest(Digest::SHA512.digest(refresh_token)),
        Digest::SHA512.digest(Digest::SHA512.hexdigest(refresh_token))
      ]
    end

    # The 64 digest bytes, or nil when the identifier is not a base64 SHA-512.
    def decode_digest
      normalized = @token.tr("-_", "+/").delete("=")
      normalized += "=" * (-normalized.length % 4)
      bytes = Base64.strict_decode64(normalized)
      bytes.bytesize == 64 ? bytes : nil
    rescue ArgumentError
      nil
    end
  end
end
