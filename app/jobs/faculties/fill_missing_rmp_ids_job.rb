# frozen_string_literal: true

module Faculties
  # Searches for and fills missing RateMyProfessor IDs for faculty who teach courses.
  # Runs before Faculties::UpdateRatingsJob so newly-approved professors get ratings immediately.
  class Faculties::FillMissingRmpIdsJob < ApplicationJob
    queue_as :low

    def perform
      missing = Faculty.with_courses.where(rmp_id: nil)

      return if missing.empty?

      Rails.logger.info "[Faculties::FillMissingRmpIdsJob] Processing #{missing.count} faculty members without RMP IDs"

      success_count   = 0
      not_found_count = 0
      error_count     = 0

      missing.find_each do |faculty|
        Faculties::UpdateRatingsJob.perform_now(faculty.id)
        faculty.reload

        if faculty.rmp_id.present?
          Rails.logger.info "[Faculties::FillMissingRmpIdsJob] Found RMP ID for #{faculty.full_name} (#{faculty.rmp_id})"
          success_count += 1
        else
          Rails.logger.debug { "[Faculties::FillMissingRmpIdsJob] No RMP ID found for #{faculty.full_name}" }
          not_found_count += 1
        end

        sleep 0.5
      rescue => e
        Rails.logger.error "[Faculties::FillMissingRmpIdsJob] Error processing #{faculty.full_name}: #{e.message}"
        error_count += 1
      end

      Rails.logger.info "[Faculties::FillMissingRmpIdsJob] Complete — success: #{success_count}, not_found: #{not_found_count}, errors: #{error_count}"
    end
  end
end
