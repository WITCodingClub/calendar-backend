# frozen_string_literal: true

module Passkeys
  # A passkey ceremony that did not finish. +reason+ is :expired (no live
  # challenge for the handle, or one for another account), :unknown (no passkey
  # with that credential id) or :rejected (the signature or a field did not
  # verify). The message is the text the API and the sign-in page show.
  class Failed < StandardError
    MESSAGES = {
      authentication: { expired: "Sign-in expired. Start again.", unknown: "Unknown passkey" },
      registration:   { expired: "Passkey registration expired. Start again." }
    }.freeze
    REJECTED = "Could not verify this passkey"

    attr_reader :reason

    def initialize(reason, ceremony:)
      @reason = reason
      super(MESSAGES.fetch(ceremony).fetch(reason, REJECTED))
    end
  end
end
