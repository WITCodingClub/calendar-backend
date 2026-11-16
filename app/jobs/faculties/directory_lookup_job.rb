# frozen_string_literal: true

module Faculties
  class DirectoryLookupJob < ApplicationJob
    queue_as :low

    def perform(faculty_id)
      faculty = Faculty.find_by(id: faculty_id)
      return unless faculty

      if faculty.directory_last_synced_at.present? && faculty.directory_last_synced_at > 24.hours.ago
        Rails.logger.info({ message: "Faculties::DirectoryLookupJob skipped - recently synced",
                            faculty_id: faculty.id, faculty_name: faculty.full_name,
                            last_synced_at: faculty.directory_last_synced_at.iso8601 }.to_json)
        return
      end

      Rails.logger.info({ message: "Faculties::DirectoryLookupJob starting",
                          faculty_id: faculty.id, faculty_name: faculty.full_name,
                          email: faculty.email, job_id: job_id }.to_json)

      result = Faculties::Directory.new(search: faculty.last_name, fetch_all: false).call

      unless result[:success]
        Rails.logger.warn({ message: "Faculties::DirectoryLookupJob search failed",
                            faculty_id: faculty.id, error: result[:error], job_id: job_id }.to_json)
        return
      end

      matching = result[:faculty].find { |f| f[:email]&.downcase == faculty.email.downcase }

      if matching
        update_faculty_from_directory(faculty, matching)
      else
        Rails.logger.info({ message: "Faculties::DirectoryLookupJob no match found",
                            faculty_id: faculty.id, faculty_name: faculty.full_name,
                            email: faculty.email, search_results_count: result[:faculty].length,
                            job_id: job_id }.to_json)
        faculty.update!(directory_last_synced_at: Time.current)
      end
    end

    private

    def update_faculty_from_directory(faculty, directory_data)
      changes = DirectoryMerge.apply(faculty, directory_data)
      if changes.any?
        Rails.logger.info({ message: "Faculties::DirectoryLookupJob updated faculty",
                            faculty_id: faculty.id, faculty_name: faculty.full_name,
                            changes: changes, job_id: job_id }.to_json)
      else
        Rails.logger.info({ message: "Faculties::DirectoryLookupJob no changes needed",
                            faculty_id: faculty.id, faculty_name: faculty.full_name, job_id: job_id }.to_json)
      end
    end
  end
end
