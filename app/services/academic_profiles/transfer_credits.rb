# frozen_string_literal: true

module AcademicProfiles
  # Stores a student's AP, test, and transfer credit (#1020). The
  # /api/user/transfer_credits endpoints use it.
  #
  # replace_transcript stores the entries that the extension reads from the
  # transfer credit section of the LeopardWeb Academic Transcript. They
  # replace the stored transcript entries. The student entries do not change:
  # a transcript entry with the code of a student entry is skipped, so a
  # later sync without that code does not remove the student's own entry.
  #
  # add stores one entry that the student adds by hand. Its code must be a
  # course in the catalog.
  class TransferCredits
    MAX_ENTRIES = 60
    # Banner prints credit hours as "4.000", so a whole number with zeros
    # after the point is a whole number.
    WHOLE_NUMBER = /\A\s*\d+(?:\.0*)?\s*\z/

    # A transcript entry the backend did not store, with the reason:
    # not_a_course_code (a generic credit such as "HUMN 1XXX"), duplicate
    # (the payload has the code two times), student_entry (the student added
    # the code), or invalid (credits or kind not valid, with the message).
    Skipped = Struct.new(:code, :reason, :message, keyword_init: true) do
      def as_json(*) = { code: code, reason: reason, message: message }.compact
    end

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # Returns the skipped entries. Raises InvalidProfileError before any write
    # when the payload is not a list of objects with a string code.
    def replace_transcript(entries)
      raise invalid("credits must be a list") unless entries.is_a?(Array)
      raise invalid("credits can have at most #{MAX_ENTRIES} entries") if entries.size > MAX_ENTRIES

      TransferCredit.transaction do
        student_codes = user.transfer_credits.student.lock.pluck(:code).to_set
        rows, skipped = transcript_rows(entries, student_codes)
        user.transfer_credits.transcript.where.not(code: rows.pluck(:code)).delete_all
        # transcript_rows validated each row with the model, and left out the
        # codes of student rows, so the upsert changes transcript rows only.
        TransferCredit.upsert_all(rows, unique_by: %i[user_id code], record_timestamps: true) if rows.any? # rubocop:disable Rails/SkipsModelValidations
        skipped
      end
    end

    # The saved student entry. credits: optional, the credit hours of the
    # catalog course when blank. Raises InvalidProfileError.
    def add(code:, credits: nil, kind: nil)
      raise invalid("code is required") unless code.is_a?(String) && code.present?

      course = CatalogCourse.find_by_code(code)
      raise invalid("#{code} is not a course in the WIT catalog", code: "unknown_course") if course.nil?
      raise invalid("#{course.code} is already in the transfer credit list", code: "duplicate") if user.transfer_credits.exists?(code: course.code)
      if user.transfer_credits.student.count >= MAX_ENTRIES
        raise invalid("A student can add at most #{MAX_ENTRIES} transfer credits", code: "too_many")
      end

      credit = user.transfer_credits.build(code: course.code, title: course.title, kind: normalize_kind(kind),
                                           credits: normalize_credits(credits).presence || course.credit_hours,
                                           source: TransferCredit::SOURCES[:student])
      raise invalid(credit.errors.full_messages.to_sentence) unless credit.save

      credit
    rescue ActiveRecord::RecordNotUnique
      raise invalid("#{course.code} is already in the transfer credit list", code: "duplicate")
    end

    private

    # [rows for upsert_all, skipped entries].
    def transcript_rows(entries, student_codes)
      skipped = []
      rows = {}
      entries.each_with_index do |entry, index|
        raise invalid("credits[#{index}] must be an object") unless entry.is_a?(Hash)

        entry = entry.with_indifferent_access
        raw = entry[:code]
        raise invalid("credits[#{index}].code must be a string") unless raw.is_a?(String)

        pair = CatalogCourse.parse_code(raw)
        next skipped << Skipped.new(code: raw, reason: "not_a_course_code") if pair.nil?

        code = pair.join(" ")
        next skipped << Skipped.new(code: code, reason: "duplicate") if rows.key?(code)
        next skipped << Skipped.new(code: code, reason: "student_entry") if student_codes.include?(code)

        row, message = transcript_row(entry, code)
        next skipped << Skipped.new(code: code, reason: "invalid", message: message) if message

        rows[code] = row
      end
      [ rows.values, skipped ]
    end

    # [row, nil], or [nil, the validation message]. One odd line of a
    # transcript does not block the other credits.
    def transcript_row(entry, code)
      credit = TransferCredit.new(user: user, code: code, title: entry[:title].presence,
                                  credits: normalize_credits(entry[:credits]), kind: normalize_kind(entry[:kind]),
                                  source: TransferCredit::SOURCES[:transcript])
      credit.validate
      # The upsert replaces a stored transcript row with the same code.
      messages = credit.errors.reject { |error| error.attribute == :code && error.type == :taken }.map(&:full_message)
      return [ nil, messages.to_sentence ] if messages.any?

      [ credit.attributes.slice("user_id", "code", "title", "credits", "source", "kind").symbolize_keys, nil ]
    end

    # 4, 4.0, "4", and "4.000" are 4. Any other value stays as it is, so the
    # validation reports it.
    def normalize_credits(value)
      case value
      when Float then value == value.floor ? value.to_i : value
      when String then value.match?(WHOLE_NUMBER) ? value.to_f.to_i : value.presence
      else value
      end
    end

    def normalize_kind(value)
      value.is_a?(String) ? value.strip.downcase.presence : value
    end

    def invalid(message, code: "invalid_transfer_credit")
      InvalidProfileError.new(message, code: code)
    end
  end
end
