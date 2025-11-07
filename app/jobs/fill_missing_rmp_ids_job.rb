# frozen_string_literal: true

# Job to automatically search for and fill in missing RateMyProfessor IDs
# This runs before the nightly RMP ratings update job so that newly approved
# professors on RMP can have their ratings fetched immediately
class FillMissingRmpIdsJob < ApplicationJob
  queue_as :low

  def perform
    missing = Faculty.where(rmp_id: nil)

    return if missing.empty?

    Rails.logger.info "FillMissingRmpIdsJob: Processing #{missing.count} faculty members without RMP IDs"

    success_count = 0
    not_found_count = 0
    error_count = 0

    missing.find_each do |faculty|
      begin
        # Use the existing UpdateFacultyRatingsJob which includes search logic
        # Run synchronously to control rate limiting
        UpdateFacultyRatingsJob.perform_now(faculty.id)

        # Reload to check if rmp_id was found
        faculty.reload

        if faculty.rmp_id.present?
          Rails.logger.info "FillMissingRmpIdsJob: Found RMP ID for #{faculty.full_name} (#{faculty.rmp_id})"
          success_count += 1
        else
          Rails.logger.debug { "FillMissingRmpIdsJob: No RMP ID found for #{faculty.full_name}" }
          not_found_count += 1
        end
      rescue => e
        Rails.logger.error "FillMissingRmpIdsJob: Error processing #{faculty.full_name}: #{e.message}"
        error_count += 1
      end

      # Small delay to avoid rate limiting
      sleep 0.5
    end

    Rails.logger.info "FillMissingRmpIdsJob: Complete - Success: #{success_count}, Not Found: #{not_found_count}, Errors: #{error_count}"
  end

end
