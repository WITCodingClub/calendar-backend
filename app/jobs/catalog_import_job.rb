# frozen_string_literal: true

class CatalogImportJob < ApplicationJob
  queue_as :low

  def perform(term_uid)
    Rails.logger.info "[CatalogImportJob] Starting import for term #{term_uid}"

    # Fetch courses from LeopardWeb (no auth required)
    result = LeopardWebService.get_course_catalog(term: term_uid)

    unless result[:success]
      Rails.logger.error "[CatalogImportJob] Failed to fetch courses: #{result[:error]}"
      raise "Failed to fetch course catalog: #{result[:error]}"
    end

    courses = result[:courses]
    Rails.logger.info "[CatalogImportJob] Fetched #{courses.count} courses for term #{term_uid}"

    if courses.empty?
      Rails.logger.warn "[CatalogImportJob] No courses found for term #{term_uid}"
      return
    end

    # Import the courses (use call! to fail loudly on errors like unknown schedule_type)
    CatalogImportService.new(courses).call!

    Rails.logger.info "[CatalogImportJob] Completed import for term #{term_uid}"
  end
end
