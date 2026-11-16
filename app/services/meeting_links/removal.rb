# frozen_string_literal: true

module MeetingLinks
  # Revokes a meeting link, or deletes it for good so it leaves the list
  # (#854). The API and the dashboard both call it. A used link keeps its
  # meeting: the owner deletes the event in the calendar to cancel it.
  module Removal
    module_function

    # Only "true" or "1" deletes. Any other value revokes, so a typo never
    # deletes a link.
    def permanent?(value) = value.to_s.in?(%w[true 1])

    # Why nothing changed, with the error code of the API. A used link
    # answers a plain revoke with the link itself, so it has no code.
    Refusal = Data.define(:message, :code)

    REFUSALS = {
      active:         Refusal.new("Revoke the link before you delete it", "MEETING_LINK_ACTIVE"),
      used_permanent: Refusal.new("A used link keeps its meeting, so it cannot be deleted", "MEETING_LINK_USED"),
      used:           Refusal.new("This link was already used. Delete the event in your calendar to cancel the meeting", nil)
    }.freeze

    # +outcome+ is :revoked, :deleted, :used (nothing changed) or :active (a
    # permanent delete of a link that still works: nothing changed).
    Result = Data.define(:outcome, :permanent) do
      def changed? = outcome.in?(%i[revoked deleted])
      def deleted? = outcome == :deleted

      def refusal
        return if changed?

        REFUSALS.fetch(outcome == :used && permanent ? :used_permanent : outcome)
      end
    end

    def call(link, permanent:)
      Result.new(outcome: remove(link, permanent), permanent: permanent)
    end

    def remove(link, permanent)
      return :used if link.used?

      if !permanent
        link.revoke!
        :revoked
      elsif link.usable?
        :active
      else
        link.destroy!
        :deleted
      end
    end
  end
end
