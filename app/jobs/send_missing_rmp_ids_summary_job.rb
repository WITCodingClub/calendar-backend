# frozen_string_literal: true

# Job to send weekly email summary of faculty missing RMP IDs
# Only sends if there are faculty members without RMP IDs
class SendMissingRmpIdsSummaryJob < ApplicationJob
  queue_as :low

  def perform
    missing_count = Faculty.where(rmp_id: nil).count

    # Only send email if there are missing RMP IDs
    if missing_count.positive?
      AdminMailer.missing_rmp_ids_summary(email: "mayonej@wit.edu").deliver_now
      Rails.logger.info "SendMissingRmpIdsSummaryJob: Sent email summary for #{missing_count} faculty without RMP IDs"
    else
      Rails.logger.info "SendMissingRmpIdsSummaryJob: Skipped - all faculty have RMP IDs"
    end
  end

end
