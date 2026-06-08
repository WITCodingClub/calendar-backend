# frozen_string_literal: true

require "open3"
require "tempfile"

class FinalsScheduleParserService < ApplicationService
  PARSERS = [
    FinalsScheduleParsers::Spring2026Parser,
    FinalsScheduleParsers::Fall2025Parser,
    FinalsScheduleParsers::SpringFallParser
  ].freeze

  attr_reader :pdf_content, :term

  def initialize(pdf_content:, term:)
    @pdf_content = pdf_content
    @term        = term
    super()
  end

  def call
    validate!

    text   = extract_pdf_text
    parser = detect_parser(text)
    Rails.logger.info("Finals schedule parser: #{parser.class.name}")

    entries = parser.parse(text)
    results = process_exam_entries(entries)

    {
      total:         entries.count,
      created:       results[:created],
      updated:       results[:updated],
      linked:        results[:linked],
      orphan:        results[:orphan],
      rooms_created: results[:rooms_created],
      errors:        results[:errors]
    }
  end

  private

  def validate!
    raise ArgumentError, "PDF content is required"      if pdf_content.blank?
    raise ArgumentError, "Term is required"             unless term.is_a?(Term)
    raise ArgumentError, "PDF content must be a string" unless pdf_content.is_a?(String)
  end

  def extract_pdf_text
    Tempfile.create(["finals_schedule", ".pdf"], binmode: true) do |tmp|
      tmp.write(pdf_content)
      tmp.flush

      stdout, stderr, status = Open3.capture3("pdftotext", tmp.path, "-")

      unless status.success?
        raise "Failed to extract text from PDF: #{stderr.presence || 'Unknown error'}. " \
              "Make sure pdftotext is installed (brew install poppler on Mac)"
      end

      stdout
    end
  end

  def detect_parser(text)
    PARSERS.each do |klass|
      return klass.new if klass.matches?(text)
    end

    ranked = PARSERS.map { |klass| { parser: klass.new, count: 0 } }
    ranked.each { |r| r[:count] = r[:parser].parse(text).count }
    best = ranked.max_by { |r| r[:count] }

    Rails.logger.warn(
      "Unknown finals PDF format; falling back to #{best[:parser].class.name} " \
      "(#{best[:count]} entries)"
    )
    best[:parser]
  end

  def process_exam_entries(entries)
    created = updated = linked = orphan = rooms_created = 0
    errors  = []

    entries.each do |entry|
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

      if final_exam.save
        was_new ? created += 1 : updated += 1
        course ? linked += 1 : orphan += 1
      else
        errors << "Failed to save final exam for CRN #{entry[:crn]}: #{final_exam.errors.full_messages.join(', ')}"
      end
    rescue => e
      errors << "Error processing CRN #{entry[:crn]}: #{e.message}"
    end

    { created: created, updated: updated, linked: linked, orphan: orphan,
      rooms_created: rooms_created, errors: errors }
  end

  def ensure_rooms_exist(location)
    return 0 if location.blank?

    rooms_created = 0

    location.split(" / ").each do |loc|
      next unless loc =~ /([A-Z]+)\s+(\d+)([A-Z])?/i

      building = Building.find_by(abbreviation: $1)
      next unless building
      next if building.rooms.exists?(number: $2.to_i)

      building.rooms.create!(number: $2.to_i)
      rooms_created += 1
      Rails.logger.info("Created room #{$2} in #{building.name}")
    end

    rooms_created
  end
end
