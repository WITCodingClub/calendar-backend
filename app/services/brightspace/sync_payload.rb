# frozen_string_literal: true

module Brightspace
  # Reads the body of POST /api/brightspace/sync into plain hashes with symbol
  # keys, and rejects what does not fit the contract in docs/brightspace.md.
  # A missing top-level field raises ActionController::ParameterMissing (400).
  # A field with a bad value raises SyncPayload::Invalid (422).
  class SyncPayload
    class Invalid < StandardError; end

    MAX_CLASSES       = 100
    MAX_SECTION_ITEMS = 2_000
    MAX_TEXT          = 20_000
    LIST_SECTIONS     = %w[assignments announcements grades].freeze

    attr_reader :snapshot_id, :host, :learner_id, :collected_at, :classes, :reconnect_required

    def initialize(raw)
      raw = raw.to_h.deep_stringify_keys

      @snapshot_id  = required_string(raw, "snapshot_id", max: 64)
      @host         = required_string(raw, "host", max: 255)
      @learner_id   = required_string(raw, "learner_id", max: 64)
      @collected_at = time(raw.fetch("collected_at") { raise ActionController::ParameterMissing, "collected_at" }, "collected_at")
      raise Invalid, "collected_at must not be in the future" if @collected_at > 5.minutes.from_now

      @reconnect_required = raw["reconnect_required"] == true

      classes = raw.fetch("classes") { raise ActionController::ParameterMissing, "classes" }
      raise Invalid, "classes must be a list" unless classes.is_a?(Array)
      raise Invalid, "classes has more than #{MAX_CLASSES} entries" if classes.size > MAX_CLASSES

      @classes = classes.each_with_index.map { |klass, index| parse_class(klass, "classes[#{index}]") }
      duplicates = @classes.group_by { |klass| klass[:source_id] }.select { |_, list| list.size > 1 }.keys
      raise Invalid, "classes lists source_id #{duplicates.first} more than once" if duplicates.any?
    end

    private

    def parse_class(raw, path)
      raise Invalid, "#{path} must be an object" unless raw.is_a?(Hash)

      complete = raw.fetch("complete_sections", [])
      raise Invalid, "#{path}.complete_sections must be a list" unless complete.is_a?(Array)

      unknown = complete - Brightspace::SECTIONS
      raise Invalid, "#{path}.complete_sections has an unknown section: #{unknown.first}" if unknown.any?

      missing = complete.reject { |section| raw.key?(section) }
      raise Invalid, "#{path}.complete_sections lists #{missing.first}, but the class has no #{missing.first}" if missing.any?

      errors = raw.fetch("section_errors", {})
      raise Invalid, "#{path}.section_errors must be an object" unless errors.is_a?(Hash)
      raise Invalid, "#{path}.section_errors has an unknown section" if (errors.keys - Brightspace::SECTIONS).any?

      klass = {
        source_id:         string(raw, "source_id", path, required: true, max: 64),
        title:             string(raw, "title", path, required: true, max: 500),
        course_id:         raw.key?("course_id") ? string(raw, "course_id", path, max: 64) : :absent,
        term_id:           raw.key?("term_id") ? string(raw, "term_id", path, max: 64) : :absent,
        complete_sections: complete.uniq,
        section_errors:    errors.to_h { |section, message| [ section, message.to_s.truncate(500) ] }
      }

      klass[:assignments]   = list(raw, "assignments", path) { |item, item_path| parse_assignment(item, item_path) } if raw.key?("assignments")
      klass[:announcements] = list(raw, "announcements", path) { |item, item_path| parse_announcement(item, item_path) } if raw.key?("announcements")
      klass[:grades]        = parse_grades(raw["grades"], "#{path}.grades") if raw.key?("grades")
      klass[:syllabus]      = parse_syllabus(raw["syllabus"], "#{path}.syllabus") if raw.key?("syllabus")
      klass
    end

    def parse_assignment(raw, path)
      kind = string(raw, "kind", path, required: true, max: 32)
      raise Invalid, "#{path}.kind must be one of #{Assignment::KINDS.join(', ')}" unless Assignment::KINDS.include?(kind)

      status = string(raw, "submission_status", path, max: 32)
      if status && !Assignment::SUBMISSION_STATUSES.include?(status)
        raise Invalid, "#{path}.submission_status must be one of #{Assignment::SUBMISSION_STATUSES.join(', ')}"
      end

      {
        kind:              kind,
        source_id:         string(raw, "source_id", path, required: true, max: 64),
        title:             string(raw, "title", path, required: true, max: 500),
        description:       string(raw, "description", path, max: MAX_TEXT),
        source_url:        url(raw, "source_url", path),
        due_at:            optional_time(raw, "due_at", path),
        opens_at:          optional_time(raw, "opens_at", path),
        closes_at:         optional_time(raw, "closes_at", path),
        user_due_at:       optional_time(raw, "user_due_at", path),
        submission_status: status,
        submitted_at:      optional_time(raw, "submitted_at", path),
        feedback:          string(raw, "feedback", path, max: MAX_TEXT)
      }
    end

    def parse_announcement(raw, path)
      {
        source_id:  string(raw, "source_id", path, required: true, max: 64),
        title:      string(raw, "title", path, required: true, max: 500),
        body:       string(raw, "body", path, max: MAX_TEXT),
        source_url: url(raw, "source_url", path),
        posted_at:  optional_time(raw, "posted_at", path)
      }
    end

    def parse_grades(raw, path)
      raise Invalid, "#{path} must be an object" unless raw.is_a?(Hash)

      {
        reported_total: parse_reported_total(raw["reported_total"], "#{path}.reported_total"),
        categories:     list(raw, "categories", path, required: false) { |item, item_path| parse_category(item, item_path) },
        items:          list(raw, "items", path, required: false) { |item, item_path| parse_grade_item(item, item_path) }
      }
    end

    def parse_reported_total(raw, path)
      return nil if raw.nil?
      raise Invalid, "#{path} must be an object" unless raw.is_a?(Hash)

      {
        "points_earned"   => number(raw, "points_earned", path)&.to_f,
        "points_possible" => number(raw, "points_possible", path)&.to_f,
        "percent"         => number(raw, "percent", path)&.to_f,
        "letter"          => string(raw, "letter", path, max: 16)
      }
    end

    def parse_category(raw, path)
      {
        source_id:    string(raw, "source_id", path, required: true, max: 64),
        name:         string(raw, "name", path, required: true, max: 500),
        weight:       number(raw, "weight", path, min: 0),
        drop_lowest:  integer(raw, "drop_lowest", path),
        drop_highest: integer(raw, "drop_highest", path),
        extra_credit: boolean(raw, "extra_credit", path)
      }
    end

    def parse_grade_item(raw, path)
      status = string(raw, "grading_status", path, required: true, max: 32)
      unless GradeItem::GRADING_STATUSES.include?(status)
        raise Invalid, "#{path}.grading_status must be one of #{GradeItem::GRADING_STATUSES.join(', ')}"
      end

      assignment_kind = string(raw, "assignment_kind", path, max: 32) || "assignment"
      raise Invalid, "#{path}.assignment_kind must be one of #{Assignment::KINDS.join(', ')}" unless Assignment::KINDS.include?(assignment_kind)

      {
        source_id:            string(raw, "source_id", path, required: true, max: 64),
        name:                 string(raw, "name", path, required: true, max: 500),
        category_source_id:   string(raw, "category_source_id", path, max: 64),
        assignment_source_id: string(raw, "assignment_source_id", path, max: 64),
        assignment_kind:      assignment_kind,
        points_earned:        number(raw, "points_earned", path),
        points_possible:      number(raw, "points_possible", path, min: 0),
        weight:               number(raw, "weight", path, min: 0),
        grading_status:       status,
        extra_credit:         boolean(raw, "extra_credit", path),
        feedback:             string(raw, "feedback", path, max: MAX_TEXT),
        graded_at:            optional_time(raw, "graded_at", path)
      }
    end

    def parse_syllabus(raw, path)
      return nil if raw.nil?
      raise Invalid, "#{path} must be an object or null" unless raw.is_a?(Hash)

      extracted = raw.fetch("extracted", {}) || {}
      raise Invalid, "#{path}.extracted must be an object" unless extracted.is_a?(Hash)
      raise Invalid, "#{path}.extracted is too large" if extracted.to_json.bytesize > 200_000

      {
        source_id:  string(raw, "source_id", path, max: 64),
        source_url: url(raw, "url", path),
        title:      string(raw, "title", path, max: 500),
        revision:   string(raw, "revision", path, required: true, max: 128),
        extracted:  extracted
      }
    end

    def list(raw, key, path, required: true, &block)
      value = raw[key]
      return [] if value.nil? && !required
      raise Invalid, "#{path}.#{key} must be a list" unless value.is_a?(Array)
      raise Invalid, "#{path}.#{key} has more than #{MAX_SECTION_ITEMS} entries" if value.size > MAX_SECTION_ITEMS

      items = value.each_with_index.map do |item, index|
        item_path = "#{path}.#{key}[#{index}]"
        raise Invalid, "#{item_path} must be an object" unless item.is_a?(Hash)

        block.call(item, item_path)
      end

      keys = items.map { |item| item.values_at(:kind, :source_id) }
      raise Invalid, "#{path}.#{key} lists one source_id more than once" if keys.uniq.size != keys.size

      items
    end

    def required_string(raw, key, max:)
      value = raw[key]
      raise ActionController::ParameterMissing, key if value.blank?

      string(raw, key, "", required: true, max: max)
    end

    def string(raw, key, path, required: false, max: 500)
      value = raw[key]
      value = value.to_s if value.is_a?(Integer)

      if value.nil? || value == ""
        raise Invalid, "#{field(path, key)} is required" if required

        return nil
      end

      raise Invalid, "#{field(path, key)} must be a string" unless value.is_a?(String)
      raise Invalid, "#{field(path, key)} is longer than #{max} characters" if value.length > max

      value
    end

    def url(raw, key, path)
      value = string(raw, key, path, max: 2_000)
      return nil if value.nil?

      uri = URI.parse(value)
      raise Invalid, "#{field(path, key)} must be an http or https URL" unless uri.is_a?(URI::HTTP) && uri.host.present?

      value
    rescue URI::InvalidURIError
      raise Invalid, "#{field(path, key)} must be an http or https URL"
    end

    def optional_time(raw, key, path)
      value = raw[key]
      return nil if value.nil?

      time(value, field(path, key))
    end

    def time(value, name)
      raise Invalid, "#{name} must be an ISO 8601 time" unless value.is_a?(String)

      Time.iso8601(value).utc
    rescue ArgumentError
      raise Invalid, "#{name} must be an ISO 8601 time"
    end

    def number(raw, key, path, min: nil)
      value = raw[key]
      return nil if value.nil?
      raise Invalid, "#{field(path, key)} must be a number" unless value.is_a?(Numeric) && value.to_f.finite?
      raise Invalid, "#{field(path, key)} must be #{min} or more" if min && value < min

      value.to_d
    end

    def integer(raw, key, path)
      value = raw[key]
      return nil if value.nil?
      raise Invalid, "#{field(path, key)} must be a whole number of 0 or more" unless value.is_a?(Integer) && value >= 0

      value
    end

    def boolean(raw, key, path)
      value = raw[key]
      return nil if value.nil?
      raise Invalid, "#{field(path, key)} must be true or false" unless [ true, false ].include?(value)

      value
    end

    def field(path, key)
      path.empty? ? key : "#{path}.#{key}"
    end
  end
end
