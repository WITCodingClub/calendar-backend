# frozen_string_literal: true

module Courses
  class Reprocessor < ApplicationService
    attr_reader :courses, :user, :term_uid

    def initialize(courses, user)
      @courses = courses
      @user = user
      if courses.is_a?(Array) && courses.any?
        first_course = courses.first
        @term_uid = first_course.is_a?(Hash) ? (first_course[:term] || first_course["term"]) : nil
      end
      super()
    end

    def call
      validate_input!

      term = Term.find_by(uid: term_uid)
      raise Courses::InvalidPayloadError, "Term with UID #{term_uid} not found" unless term

      Rails.logger.info("[CourseReprocess] Starting for user #{user.id} (#{user.email}), term #{term.uid}")

      current_enrollments = user.enrollments.includes(:course).where(term: term)
      current_crns        = current_enrollments.map { |e| e.course.crn }

      @courses = courses.map { |c| c.deep_symbolize_keys }
      new_crns = @courses.map { |c| c[:crn].to_i }

      crns_to_remove = current_crns - new_crns

      Rails.logger.info("[CourseReprocess] User #{user.id}: CRNs to remove: #{crns_to_remove.inspect}")
      Rails.logger.info("[CourseReprocess] User #{user.id}: New CRNs: #{new_crns.inspect}")

      enrollments_to_remove = current_enrollments.select { |e| crns_to_remove.include?(e.course.crn) }
      removed_courses = []

      enrollments_to_remove.each do |enrollment|
        course = enrollment.course
        removed_courses << { crn: course.crn, title: course.title, course_number: course.course_number }
        enrollment.destroy!
      end

      # The processor starts a sync (CourseCalendars.resync). The sync deletes
      # the calendar events of the removed courses in every provider.
      processed_courses = Courses::Processor.new(courses, user).call

      Rails.logger.info("[CourseReprocess] User #{user.id}: Done — removed #{removed_courses.count} enrollments")

      user.update(calendar_needs_sync: true)

      {
        removed_enrollments: removed_courses.count,
        removed_courses:     removed_courses,
        processed_courses:   processed_courses
      }
    end

    private

    def validate_input!
      raise Courses::InvalidPayloadError, "courses cannot be nil"   if courses.nil?
      raise Courses::InvalidPayloadError, "courses must be an array" unless courses.is_a?(Array)
      raise Courses::InvalidPayloadError, "courses cannot be empty"  if courses.empty?

      term_uids = courses.map { |c| c[:term] || c["term"] }.uniq
      raise Courses::InvalidPayloadError, "All courses must be from the same term" if term_uids.length > 1

      # Check the whole payload before any enrollment is removed below. A
      # payload that Courses::Processor refuses must not cost the user their
      # enrollments and calendar events.
      Courses::Processor.new(courses, user).validate!
    end
  end
end
