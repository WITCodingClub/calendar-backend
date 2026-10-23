# frozen_string_literal: true

module FinalsSchedules
  # Parses a finals PDF and saves one FinalExam per CRN for the term.
  #
  # With dry_run: true, the service makes the same changes in a transaction
  # and rolls it back. The result then shows what an upload would change.
  class Parser < ApplicationService
    TRACKED_ATTRIBUTES = %w[exam_date start_time end_time location combined_crns].freeze

    attr_reader :pdf_content, :term, :dry_run

    def initialize(pdf_content:, term:, dry_run: false)
      @pdf_content = pdf_content
      @term        = term
      @dry_run     = dry_run
      super()
    end

    def call
      validate!

      parser  = TableParser.new
      entries = parser.parse(PdfText.extract(pdf_content))
      results = dry_run ? rolled_back { process_exam_entries(entries) } : process_exam_entries(entries)

      {
        total:         entries.count,
        created:       results[:created],
        updated:       results[:updated],
        linked:        results[:linked],
        orphan:        results[:orphan],
        rooms_created: results[:rooms_created],
        changes:       results[:changes],
        stale_crns:    FinalExam.where(term: term).where.not(crn: entries.pluck(:crn)).order(:crn).pluck(:crn),
        errors:        parser.warnings + results[:errors]
      }
    end

    private

    def validate!
      raise ArgumentError, "PDF content is required"      if pdf_content.blank?
      raise ArgumentError, "Term is required"             unless term.is_a?(Term)
      raise ArgumentError, "PDF content must be a string" unless pdf_content.is_a?(String)
    end

    def rolled_back
      result = nil
      ActiveRecord::Base.transaction do
        result = yield
        raise ActiveRecord::Rollback
      end
      result
    end

    def process_exam_entries(entries)
      created = updated = linked = orphan = rooms_created = 0
      errors  = []
      changes = []

      entries.each do |entry|
        # A savepoint for each entry: in a dry run, one database error rolls
        # back only this entry, not the transaction that the others share.
        ActiveRecord::Base.transaction(requires_new: true) do
          rooms_created += ensure_rooms_exist(entry[:location])

          final_exam = FinalExam.find_or_initialize_by(crn: entry[:crn], term: term)
          was_new    = final_exam.new_record?
          course     = Course.find_by(crn: entry[:crn], term: term)

          final_exam.assign_attributes(
            course:        course,
            exam_date:     entry[:date],
            start_time:    entry[:start_time],
            end_time:      entry[:end_time],
            location:      entry[:location],
            combined_crns: entry[:combined_crns]
          )
          diff = final_exam.changes.slice(*TRACKED_ATTRIBUTES)

          if final_exam.save
            was_new ? created += 1 : updated += 1
            course ? linked += 1 : orphan += 1
            changes << { crn: entry[:crn], action: was_new ? :create : :update, changes: diff } if was_new || diff.any?
          else
            errors << "Failed to save final exam for CRN #{entry[:crn]}: #{final_exam.errors.full_messages.join(', ')}"
          end
        end
      rescue => e
        Rails.error.report(e, handled: true, context: { crn: entry[:crn] })
        errors << "Error processing CRN #{entry[:crn]}: #{e.message}"
      end

      { created: created, updated: updated, linked: linked, orphan: orphan,
        rooms_created: rooms_created, changes: changes, errors: errors }
    end

    def ensure_rooms_exist(location)
      return 0 if location.blank?

      rooms_created = 0

      location.split(" / ").each do |loc|
        next unless loc =~ FinalExam::ROOM_PATTERN

        abbrev = $1
        number = $2.upcase
        building = Building.find_by(abbreviation: abbrev)
        next unless building
        next if building.rooms.any? { |room| Room.number_key(room.number) == Room.number_key(number) }

        building.rooms.create!(number: number)
        rooms_created += 1
        Rails.logger.info("Created room #{number} in #{building.name}")
      end

      rooms_created
    end
  end
end
