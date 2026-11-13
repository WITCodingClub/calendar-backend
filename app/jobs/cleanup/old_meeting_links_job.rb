# frozen_string_literal: true

module Cleanup
  # Deletes the one-time meeting links that were never used and stopped
  # working (revoked or expired) more than MeetingLink::KEEP_STOPPED_FOR ago,
  # so they leave the owner's list (#854). A used link keeps its booking and
  # stays. No other table points to a meeting link, so delete_all is safe.
  class OldMeetingLinksJob < ApplicationJob
    queue_as :low

    def perform
      deleted = MeetingLink.stopped_before(MeetingLink::KEEP_STOPPED_FOR.ago).delete_all

      Rails.logger.info "[Cleanup::OldMeetingLinksJob] Deleted #{deleted} old meeting links"
    end
  end
end
