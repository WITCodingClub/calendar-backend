# frozen_string_literal: true

module Brightspace
  # Stores one snapshot from the extension. The rules, from docs/brightspace.md:
  #
  # - A section that the payload leaves out stays as it is.
  # - Only a section in complete_sections can mark rows as removed, and only
  #   rows of that class.
  # - A section with an error in section_errors keeps its data.
  # - A section that a newer snapshot already wrote is skipped.
  # - The same snapshot again is a no-op. The same snapshot id with other
  #   data is a conflict.
  #
  # The whole snapshot is one transaction, so a failure keeps the old data.
  class SyncIngestor
    class Conflict < StandardError
      attr_reader :code

      def initialize(message, code:)
        super(message)
        @code = code
      end
    end

    Result = Data.define(:body, :sync, :replayed)

    def initialize(user:, params:)
      @user   = user
      @params = params
    end

    def call
      payload    = SyncPayload.new(@params)
      digest     = Digest::SHA256.hexdigest(JSON.generate(canonical(@params.to_h)))
      connection = @user.brightspace_connections.active.first

      raise Conflict.new("No Brightspace account is linked", code: "NOT_CONNECTED") unless connection
      unless connection.matches?(host: payload.host, learner_id: payload.learner_id)
        raise Conflict.new("The snapshot is for a different Brightspace account than the linked one", code: "CONNECTION_MISMATCH")
      end

      @assignments_changed = false

      result = connection.with_lock do
        existing = connection.syncs.find_by(snapshot_id: payload.snapshot_id)
        if existing
          raise Conflict.new("snapshot_id was already used with different data", code: "SNAPSHOT_CONFLICT") if existing.payload_digest != digest

          next Result.new(body: existing.result, sync: existing, replayed: true)
        end

        @now      = Time.current
        @payload  = payload
        @warnings = []
        changed   = payload.classes.filter_map { |klass| import_class(connection, klass) }

        sync = connection.syncs.create!(snapshot_id: payload.snapshot_id, payload_digest: digest,
                                        collected_at: payload.collected_at, status: "complete")
        body = {
          "sync_id"         => sync.public_id,
          "status"          => "complete",
          "changed_classes" => changed.map { |offering| { "id" => offering.public_id, "version" => offering.version } },
          "warnings"        => @warnings
        }
        sync.update!(result: body)
        connection.update!(last_synced_at: @now, reconnect_required_at: payload.reconnect_required ? @now : nil)

        Result.new(body: body, sync: sync, replayed: false)
      end

      Brightspace.queue_calendar_sync(@user) if @assignments_changed
      result
    end

    private

    # Returns the offering when its data changed.
    def import_class(connection, klass)
      offering = connection.course_offerings.find_or_initialize_by(source_id: klass[:source_id])
      new_record = offering.new_record?

      offering.title = klass[:title]
      map_course(offering, klass)
      changed = offering.changed? && !new_record
      offering.save! if offering.changed?

      sections = offering.sections.deep_dup
      Brightspace::SECTIONS.each do |section|
        next unless klass.key?(section.to_sym) || klass[:section_errors].key?(section)
        next if newer_data?(sections[section])

        if klass[:section_errors].key?(section)
          sections[section] = (sections[section] || {}).merge("error" => klass[:section_errors][section], "failed_at" => @payload.collected_at.iso8601)
          next
        end

        complete = klass[:complete_sections].include?(section)
        changed |= send(:"import_#{section}", offering, klass[section.to_sym], complete: complete)
        sections[section] = { "collected_at" => @payload.collected_at.iso8601, "complete" => complete, "error" => nil }
      end

      offering.update!(sections: sections) if sections != offering.sections
      return offering if new_record

      return nil unless changed

      offering.bump_version!
      offering
    end

    # A class can link to a course only from the user's own enrollments. A
    # course id that is not one is ignored with a warning, so the rest of the
    # snapshot still imports.
    def map_course(offering, klass)
      unless klass[:course_id] == :absent || klass[:course_id].nil?
        course = Course.find_by_public_id(klass[:course_id])
        if course && @user.enrollments.exists?(course_id: course.id)
          offering.course = course
          offering.term   = course.term
        else
          @warnings << { "class_source_id" => klass[:source_id], "message" => "course_id is not one of your enrolled courses" }
        end
      end

      return if klass[:term_id] == :absent || klass[:term_id].nil? || offering.course

      term = Term.find_by_public_id(klass[:term_id])
      if term
        offering.term = term
      else
        @warnings << { "class_source_id" => klass[:source_id], "message" => "term_id is not a known term" }
      end
    end

    def newer_data?(state)
      collected_at = state&.dig("collected_at")
      collected_at.present? && Time.iso8601(collected_at) > @payload.collected_at
    end

    def import_assignments(offering, items, complete:)
      existing = offering.assignments.index_by { |row| [ row.kind, row.source_id ] }
      changed  = upsert_rows(offering.assignments, existing, items, complete: complete,
                             before_save: method(:record_deadline_changes)) { |item| [ item[:kind], item[:source_id] ] }
      @assignments_changed ||= changed
      changed
    end

    # Records each date that moved on an assignment that existed before, so a
    # notifier can tell the user.
    def record_deadline_changes(row)
      return if row.new_record?

      (Brightspace::DeadlineChange::FIELDS & row.changed).each do |field|
        previous, current = row.changes[field]
        row.deadline_changes.build(field: field, previous_at: previous, current_at: current, detected_at: @now)
      end
    end

    def import_announcements(offering, items, complete:)
      existing = offering.announcements.index_by(&:source_id)
      upsert_rows(offering.announcements, existing, items, complete: complete) { |item| item[:source_id] }
    end

    def import_grades(offering, grades, complete:)
      changed = false

      if grades[:reported_total] != offering.reported_total
        offering.update!(reported_total: grades[:reported_total])
        changed = true
      end

      categories = offering.grade_categories.index_by(&:source_id)
      changed |= upsert_rows(offering.grade_categories, categories, grades[:categories], complete: complete) { |item| item[:source_id] }

      categories  = offering.grade_categories.reload.index_by(&:source_id)
      assignments = offering.assignments.index_by { |row| [ row.kind, row.source_id ] }
      items = grades[:items].map do |item|
        attributes = item.except(:category_source_id, :assignment_source_id, :assignment_kind)
        attributes[:grade_category_id] = categories[item[:category_source_id]]&.id
        attributes[:assignment_id]     = assignments[[ item[:assignment_kind], item[:assignment_source_id] ]]&.id
        attributes
      end

      existing = offering.grade_items.index_by(&:source_id)
      changed | upsert_rows(offering.grade_items, existing, items, complete: complete) { |item| item[:source_id] }
    end

    def import_syllabus(offering, syllabus, complete:)
      row = offering.syllabus

      if syllabus.nil?
        return false unless complete && row && !row.removed?

        row.update!(removed_at: @now)
        return true
      end

      row ||= offering.build_syllabus
      row.assign_attributes(syllabus.merge(removed_at: nil))
      return false unless row.changed?

      row.save!
      true
    end

    # Writes each item to its row, and marks unlisted rows as removed when the
    # section is complete. Returns true when any row changed.
    def upsert_rows(association, existing, items, complete:, before_save: nil, &key_for)
      changed = false
      seen    = []

      items.each do |item|
        row = existing[key_for.call(item)] || association.build
        row.assign_attributes(item.merge(removed_at: nil))
        seen << row

        next unless row.changed?

        before_save&.call(row)
        row.save!
        changed = true
      end

      return changed unless complete

      removed = association.not_removed.where.not(id: seen.map(&:id))
                           .update_all(removed_at: @now, updated_at: @now) # rubocop:disable Rails/SkipsModelValidations
      changed || removed.positive?
    end

    # Sorts hash keys, so the same data in another key order has one digest.
    def canonical(value)
      case value
      when Hash  then value.to_h { |key, inner| [ key.to_s, canonical(inner) ] }.sort.to_h
      when Array then value.map { |inner| canonical(inner) }
      else value
      end
    end
  end
end
