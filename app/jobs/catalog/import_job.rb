# frozen_string_literal: true

module Catalog
  class ImportJob < ApplicationJob
    queue_as :low

    def perform(term_uid)
      Rails.logger.info "[Catalog::ImportJob] Starting import for term #{term_uid}"

      result = Catalog::LeopardWebClient.get_course_catalog(term: term_uid)

      unless result[:success]
        Rails.logger.error "[Catalog::ImportJob] Failed to fetch courses: #{result[:error]}"
        raise "Failed to fetch course catalog: #{result[:error]}"
      end

      courses = result[:courses]
      Rails.logger.info "[Catalog::ImportJob] Fetched #{courses.count} courses for term #{term_uid}"

      if courses.empty?
        Rails.logger.warn "[Catalog::ImportJob] No courses found for term #{term_uid}"
        return
      end

      Catalog::Importer.new(courses).call!

      Rails.logger.info "[Catalog::ImportJob] Completed import for term #{term_uid}"
    rescue => e
      Term.where(uid: term_uid).update_all(catalog_import_failed: true)
      raise
    ensure
      Term.where(uid: term_uid).update_all(catalog_importing: false)
    end
  end
end
