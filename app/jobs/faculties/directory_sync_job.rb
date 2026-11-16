# frozen_string_literal: true

module Faculties
  class DirectorySyncJob < ApplicationJob
    queue_as :low

    # Faculty#enqueue_directory_lookup reads this key: after a full sync, a new
    # faculty row needs no lookup of its own.
    LAST_FULL_SYNC_CACHE_KEY = "faculty_directory_last_full_sync_at"

    def perform
      Rails.logger.info({ message: "Faculties::DirectorySyncJob starting", job_id: job_id }.to_json)

      # force: true fetches every page again and overwrites the cached pages.
      # Solid Cache has no delete_matched, so the job cannot clear them by pattern.
      result = Faculties::Directory.call(force: true)

      unless result[:success]
        Rails.logger.error({ message: "Faculties::DirectorySyncJob failed to fetch directory",
                             error: result[:error], job_id: job_id }.to_json)
        raise "Failed to fetch faculty directory: #{result[:error]}"
      end

      stats = { created: 0, updated: 0, skipped: 0, errors: [] }

      emails = result[:faculty].filter_map { |f| f[:email]&.downcase&.strip }.uniq
      @faculty_cache = Faculty.where(email: emails).index_by(&:email)

      result[:faculty].each { |faculty_data| process_faculty(faculty_data, stats) }

      Rails.cache.write(LAST_FULL_SYNC_CACHE_KEY, Time.current, expires_in: 2.days)

      Rails.logger.info({ message: "Faculties::DirectorySyncJob completed", job_id: job_id,
                          total_fetched: result[:total_count], created: stats[:created],
                          updated: stats[:updated], skipped: stats[:skipped],
                          errors_count: stats[:errors].length }.to_json)

      stats
    end

    private

    def process_faculty(faculty_data, stats)
      email = faculty_data[:email]&.downcase&.strip
      if email.blank?
        stats[:skipped] += 1
        return
      end

      faculty = @faculty_cache&.fetch(email, nil) || Faculty.new(email: email)
      was_new = faculty.new_record?

      if was_new && DirectoryMerge.name_parts(faculty_data[:display_name]).values_at(:first_name, :last_name).any?(&:blank?)
        stats[:skipped] += 1
        return
      end

      if DirectoryMerge.apply(faculty, faculty_data).any?
        was_new ? stats[:created] += 1 : stats[:updated] += 1
      else
        stats[:skipped] += 1
      end
    rescue => e
      Rails.error.report(e, handled: true, context: { faculty_id: faculty&.id })
      Rails.logger.error({ message: "Faculties::DirectorySyncJob error processing faculty",
                           email: email, error: e.message, job_id: job_id }.to_json)
      stats[:errors] << { email: email, error: e.message }
    end
  end
end
