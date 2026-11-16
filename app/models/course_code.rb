# frozen_string_literal: true

# The code of a course, such as COMP 2350: a subject code and a number.
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

  def format(subject_code, course_number) = "#{subject_code} #{course_number}"

  # "Computer Science (COMP)", "COMP", or "comp" to "COMP". A subject with
  # no code, such as "Climate Resilience", stays as it is.
  def subject_of(subject)
    subject = subject.to_s.strip
    code = subject[LABEL_SUFFIX, 1] || subject
    code.upcase.match?(BARE_SUBJECT) ? code.upcase : code
  end

  # subject_of in SQL, for a column that holds a subject label.
  def subject_sql(column)
    "UPPER(BTRIM(COALESCE(SUBSTRING(#{column} FROM '\\(([A-Z0-9]{2,6})\\)\\s*$'), #{column})))"
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
