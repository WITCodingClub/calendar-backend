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

    # Returns :revoked, :deleted, :used (nothing changed) or :active (a
    # permanent delete of a link that still works: nothing changed).
    def call(link, permanent:)
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
