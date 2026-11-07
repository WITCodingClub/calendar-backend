# frozen_string_literal: true

module Faculties
  # The weekly RateMyProfessor refresh. Each professor who teaches in a current
  # or future term gets one Faculties::UpdateRatingsJob. A professor with no
  # rmp_id is searched first, and then gets ratings in the same job.
  #
  # Before this job, a run at 2am enqueued the professors with no rmp_id, and a
  # run at 3am enqueued every professor. Jobs from 2am that had not run by 3am
  # got a second job, and the professor was searched twice. Now each professor
  # gets one job, and the professors with no rmp_id are enqueued first, so
  # Faculties::UpdateRatingsJob's concurrency limit runs them first.
  #
  # The jobs are one Solid Queue batch. When the last one ends, the batch
  # embeds the new and changed reviews (Embeddings::BackfillJob).
  class RefreshRatingsJob < ApplicationJob
    queue_as :low

    def perform
      scope = Faculty.teaching_current_or_future
      ids = scope.where(rmp_id: nil).order(:id).pluck(:id) + scope.where.not(rmp_id: nil).order(:id).pluck(:id)

      SolidQueue::Batch.enqueue(description: "RateMyProfessor refresh",
                                on_finish: Embeddings::BackfillJob.new("RmpRating"),
                                faculty_count: ids.size) do
        ActiveJob.perform_all_later(ids.map { |id| Faculties::UpdateRatingsJob.new(id) })
      end

      Rails.logger.info "[Faculties::RefreshRatingsJob] Enqueued Faculties::UpdateRatingsJob for #{ids.size} faculty members"
    end
  end
end
