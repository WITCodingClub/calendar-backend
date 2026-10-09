# frozen_string_literal: true

module Faculties
  # Searches for and fills missing RateMyProfessor IDs for faculty who teach courses.
  # Runs before Faculties::UpdateRatingsJob so newly-approved professors get ratings immediately.
  #
  # Each professor gets its own Faculties::UpdateRatingsJob. That job searches
  # RateMyProfessor when the rmp_id is blank, and its concurrency limit keeps
  # the request rate low. This job does not hold a worker thread for the whole
  # run (#712).
  class Faculties::FillMissingRmpIdsJob < ApplicationJob
    queue_as :low

    def perform
      missing = Faculty.teaching_current_or_future.where(rmp_id: nil)

      count = 0
      missing.find_each do |faculty|
        Faculties::UpdateRatingsJob.perform_later(faculty.id)
        count += 1
      end

      Rails.logger.info "[Faculties::FillMissingRmpIdsJob] Enqueued Faculties::UpdateRatingsJob for #{count} faculty members without RMP IDs"
    end
  end
end
