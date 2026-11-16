# frozen_string_literal: true

module AcademicProfiles
  # Stores a student's AP, test, and transfer credit (#1020). The
  # /api/user/transfer_credits endpoints use it.
  #
  # replace_transcript stores the entries that the extension reads from the
  # transfer credit section of the LeopardWeb Academic Transcript. They
  # replace the stored transcript entries. A student entry with the same code
  # becomes a transcript entry. Other student entries do not change.
  #
  # add stores one entry that the student adds by hand. Its code must be a
  # course in the catalog.
  class TransferCredits
    MAX_ENTRIES = 60

    # A transcript entry the backend did not store: its code is not a WIT
    # course code (a generic credit such as "HUMN 1XXX"), or the payload has
    # the code two times.
    Skipped = Struct.new(:code, :reason, keyword_init: true) do
      def as_json(*) = { code: code, reason: reason }
    end

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # Returns the skipped entries. Raises InvalidProfileError before any write
    # when the payload or an entry is not valid.
    def replace_transcript(entries)
      raise invalid("credits must be a list") unless entries.is_a?(Array)
      raise invalid("credits can have at most #{MAX_ENTRIES} entries") if entries.size > MAX_ENTRIES

      rows, skipped = transcript_rows(entries)
      TransferCredit.transaction do
        user.transfer_credits.where(source: TransferCredit::SOURCES[:transcript]).where.not(code: rows.pluck(:code)).delete_all
        # transcript_rows validated each row with the model.
        TransferCredit.upsert_all(rows, unique_by: %i[user_id code], record_timestamps: true) if rows.any? # rubocop:disable Rails/SkipsModelValidations
      end
      skipped
    end

    # The saved student entry. credits: optional, the credit hours of the
    # catalog course when blank. Raises InvalidProfileError.
    def add(code:, credits: nil, kind: nil)
      raise invalid("code is required") unless code.is_a?(String) && code.present?

      course = CatalogCourse.find_by_code(code)
      raise invalid("#{code} is not a course in the WIT catalog", code: "unknown_course") if course.nil?
      if user.transfer_credits.exists?(code: course.code)
        raise invalid("#{course.code} is already in the transfer credit list", code: "duplicate")
      end

      credit = user.transfer_credits.build(code: course.code, title: course.title, kind: kind.presence,
                                           credits: credits.presence || course.credit_hours,
                                           source: TransferCredit::SOURCES[:student])
      raise invalid(credit.errors.full_messages.to_sentence) unless credit.save

      credit
    rescue ActiveRecord::RecordNotUnique
      raise invalid("#{course.code} is already in the transfer credit list", code: "duplicate")
    end

    private

    # [rows for upsert_all, skipped entries].
    def transcript_rows(entries)
      skipped = []
      rows = {}
      entries.each_with_index do |entry, index|
        raise invalid("credits[#{index}] must be an object") unless entry.is_a?(Hash)

        entry = entry.with_indifferent_access
        raw = entry[:code]
        raise invalid("credits[#{index}].code must be a string") unless raw.is_a?(String)

        pair = CatalogCourse.parse_code(raw)
        if pair.nil?
          skipped << Skipped.new(code: raw, reason: "not_a_course_code")
          next
        end

        code = pair.join(" ")
        if rows.key?(code)
          skipped << Skipped.new(code: code, reason: "duplicate")
          next
        end

        rows[code] = transcript_row(entry, code, index)
      end
      [ rows.values, skipped ]
    end

    def transcript_row(entry, code, index)
      credit = TransferCredit.new(user: user, code: code, title: entry[:title].presence, credits: entry[:credits],
                                  kind: entry[:kind].presence, source: TransferCredit::SOURCES[:transcript])
      credit.validate
      # The upsert replaces a stored row with the same code.
      messages = credit.errors.reject { |error| error.attribute == :code && error.type == :taken }.map(&:full_message)
      raise invalid("credits[#{index}]: #{messages.to_sentence}") if messages.any?

      credit.attributes.slice("user_id", "code", "title", "credits", "source", "kind").symbolize_keys
    end

    def invalid(message, code: "invalid_transfer_credit")
      InvalidProfileError.new(message, code: code)
    end
  end
end
