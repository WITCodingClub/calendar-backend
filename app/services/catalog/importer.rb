# frozen_string_literal: true

module Catalog
  class Importer < ApplicationService
    attr_reader :catalog_courses

    def initialize(catalog_courses)
      @catalog_courses = catalog_courses
      super()
    end

    def call
      validate_courses_data!

      processed_count = 0
      processed_terms = Set.new
      failed_courses = []
      @changes = { created: 0, updated: 0, unchanged: 0 }

      unique_courses = catalog_courses.uniq { |c| [ c["courseReferenceNumber"], c["term"] ] }

      term_uids = unique_courses.map { |c| c["term"] || c["termEffective"] }.compact.uniq

      # Load what every course shares once: the terms, the instructors, and the
      # buildings and rooms as the courses name them (#729).
      @terms = Term.where(uid: term_uids).index_by { |t| t.uid.to_s }
      @faculty = Faculties::Ingest.preload(unique_courses.map { |c| c["faculty"] || [] })
      @locations = Catalog::MeetingTimesIngest::Locations.new

      missing = term_uids.reject { |uid| @terms.key?(uid.to_s) }
      if missing.any?
        raise ArgumentError, "Terms not found in database: #{missing.join(', ')}. Create them before importing."
      end

      unique_courses.each_with_index do |course_data, index|
        begin
          process_course(course_data)
          processed_count += 1
          processed_terms << (course_data["term"] || course_data["termEffective"]).to_s
        rescue => e
          Rails.error.report(e, handled: true, context: { crn: course_data["courseReferenceNumber"], term: course_data["term"] })
          failed_courses << {
            crn: course_data["courseReferenceNumber"],
            term: course_data["term"],
            error: e.message
          }
        end

        if (index + 1) % 50 == 0
          Rails.logger.info("Processed #{index + 1}/#{unique_courses.count} courses")
        end
      end

      term_uids.each do |term_uid|
        term = @terms[term_uid.to_s]
        next unless term && processed_terms.include?(term_uid.to_s)

        term.update!(
          catalog_imported: true,
          catalog_imported_at: Time.current
        )
        Rails.logger.info("Marked term #{term_uid} (#{term.name}) as catalog_imported")
      end

      {
        total: unique_courses.count,
        processed: processed_count,
        failed: failed_courses.count,
        failed_courses: failed_courses,
        **@changes
      }
    end

    def call!
      result = call
      raise "Failed to process #{result[:failed]} courses" if result[:failed] > 0

      result
    end

    private

    def process_course(course_data)
      section = BannerSection.from_search(course_data)
      crn = section.crn
      term = @terms.fetch(section.term_uid.to_s)
      schedule_type = section.schedule_type
      raise "Unknown or missing schedule type '#{section.schedule_type_text}' for CRN #{crn}" unless schedule_type

      details = section.attributes
      start_date, end_date = section_dates(section, term)
      if start_date.nil? || end_date.nil?
        raise "Cannot determine dates for CRN #{crn}: no meeting times and term #{term.uid} (#{term.name}) has no dates set"
      end

      # Re-importing a term is how existing rows learn their link identifier
      # and the other details, so these are written on update too.
      update_attrs = details.slice(:title, :credit_hours, :link_identifier, :is_section_linked,
                                   :part_of_term, :campus, :cross_list_identifier)
                            .merge(start_date: start_date, end_date: end_date, **section.counts)

      course = Course.find_or_create_by!(crn: crn, term: term) do |c|
        c.assign_attributes(update_attrs)
        c.subject = Catalog::SubjectLabels.label(details[:subject_description], details[:subject_code])
        c.course_number = details[:course_number]
        c.schedule_type = schedule_type
        c.section_number = details[:section_number]
      end

      if course.previously_new_record?
        @changes[:created] += 1
      else
        # The counts cover the section row. Meeting times and instructors can
        # still change below while the section counts as unchanged.
        course.assign_attributes(update_attrs)
        changed = course.changed?
        course.save! if changed
        @changes[changed ? :updated : :unchanged] += 1
      end

      orphan_exam = FinalExam.orphan.find_by(crn: course.crn, term: term)
      if orphan_exam
        orphan_exam.update!(course: course)
        Rails.logger.info("Linked FinalExam for CRN #{course.crn} to course #{course.id}")
      end

      if section.meeting_times.any?
        kept_ids = Catalog::MeetingTimesIngest.call(course: course, meetings: section.meeting_times, locations: @locations)

        # Remove meeting times that no longer exist upstream (e.g. Banner changed a
        # section's day/time), but only when the ingest produced rows — never wipe
        # the course from an empty result. Preserves untouched rows and their events.
        course.meeting_times.where.not(id: kept_ids).destroy_all if kept_ids.any?
      else
        Rails.logger.warn("No meeting times found for course CRN #{crn}")
      end

      if section.faculty.any?
        Faculties::Ingest.call(course: course, raw_faculty: section.faculty, faculty: @faculty)
      else
        Rails.logger.warn("No faculty data found for course CRN #{crn}")
      end

      course
    end

    # The dates of the first meeting, or the term's dates when there is no
    # meeting or Banner's dates are outside the term.
    def section_dates(section, term)
      first = section.meeting_times.first
      return [ first.start_date, first.end_date ] if first && term.section_dates?(first.start_date, first.end_date)

      if first
        Rails.logger.warn("Invalid dates for term #{term.name}: #{first.start_date} to #{first.end_date}, using term defaults")
      end
      [ term.start_date, term.end_date ]
    end

    def validate_courses_data!
      raise ArgumentError, "catalog_courses cannot be nil" if catalog_courses.nil?
      raise ArgumentError, "catalog_courses must be an array" unless catalog_courses.is_a?(Array)
      raise ArgumentError, "catalog_courses cannot be empty" if catalog_courses.empty?

      catalog_courses.each_with_index do |course_data, index|
        unless course_data.is_a?(Hash)
          raise ArgumentError, "course at index #{index} must be a hash"
        end

        crn = course_data["courseReferenceNumber"] || course_data["crn"]
        if crn.blank?
          available_keys = course_data.keys.first(15).join(", ")
          raise ArgumentError, "course at index #{index} missing required field: courseReferenceNumber or crn. Available keys: #{available_keys}"
        end

        term_uid = course_data["term"] || course_data["termEffective"]
        if term_uid.blank?
          raise ArgumentError, "course at index #{index} missing required field: term or termEffective"
        end

        unless term_uid.to_s.match?(/^\d+$/)
          raise ArgumentError, "course at index #{index} has invalid term UID: #{term_uid}"
        end
      end
    end
  end
end
