# frozen_string_literal: true

# The code of a course, such as COMP 2350: a subject code and a number. A
# course key is the pair, ["COMP", 2350]. Code and key are the only two forms
# of a course name: CourseCode.parse makes the key of a code, and
# CourseCode.format the code of a key.
#
# Banner stores a section's subject as a label, "Computer Science (COMP)",
# and some old rows as the bare code, "COMP". The subject code is the code in
# the parentheses at the end, or the whole subject. "(optional)" is not a code
# (Catalog::SubjectLabels). CatalogCourse and the catalog rows store the
# subject code alone.
module CourseCode
  # "COMP2350", "COMP 2350", or "comp-2350".
  PATTERN = /\A\s*([A-Za-z]{2,5})\s*-?\s*(\d{3,4})\s*\z/
  # The subject code at the end of a label.
  LABEL_SUFFIX = /\(([A-Z0-9]{2,6})\)\s*\z/
  # A subject that is a bare code.
  BARE_SUBJECT = /\A[A-Z0-9]{2,6}\z/

  module_function

  # ["COMP", 2350], or nil when the text is not a course code.
  def parse(text)
    match = PATTERN.match(text.to_s)
    match && [ match[1].upcase, match[2].to_i ]
  end

  # "COMP 2350", the form of every code in a response. Takes the two parts,
  # or a key: format(*key).
  def format(subject_code, course_number) = "#{subject_code} #{course_number}"

  # "comp2350" as "COMP 2350", or nil when the text is not a course code.
  def normalize(text)
    key = parse(text)
    key && format(*key)
  end

  # The key of a JSON course reference, such as a prerequisite node or an
  # option of a choice: { "subject_code" => "COMP", "course_number" => 2350 }.
  def key_of(hash) = [ hash["subject_code"], hash["course_number"].to_i ]

  # The key and code of a record or value with subject_code and
  # course_number.
  module Named
    def key = [ subject_code, course_number ]

    def code
      CourseCode.format(subject_code, course_number) if subject_code && course_number
    end
  end

  # A table with subject_code and course_number columns.
  module Record
    extend ActiveSupport::Concern
    include Named

    included do
      # Keys, such as [["COMP", 2350]].
      scope :by_codes, ->(keys) { keys.empty? ? none : where([ :subject_code, :course_number ] => keys.uniq) }
    end
  end

  # "Computer Science (COMP)", "COMP", or "comp" to "COMP". A subject with
  # no code, such as "Climate Resilience", stays as it is.
  def subject_of(subject)
    subject = subject.to_s.strip
    code = subject[LABEL_SUFFIX, 1] || subject
    code.upcase.match?(BARE_SUBJECT) ? code.upcase : code
  end

  # A condition that keeps the rows whose subject column has one of the
  # subject codes, as the bare code or as a label that ends in "(CODE)". It
  # can use the index on the column, which subject_sql cannot.
  #
  # @return [Array] the SQL and its binds, for where
  def subject_condition(column, codes)
    sql = codes.map { "(#{column} = ? OR #{column} ILIKE ?)" }.join(" OR ")
    [ sql, *codes.flat_map { |code| [ code, "%(#{ActiveRecord::Base.sanitize_sql_like(code)})" ] } ]
  end
end
