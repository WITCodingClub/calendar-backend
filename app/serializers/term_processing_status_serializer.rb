# frozen_string_literal: true

# Response of POST /api/user/is_processed.
#
# "processed" stays a boolean for older extension versions. It is true only
# when the term is fully processed. "status" and "error_code" let the
# extension stop its poll when a term failed.
#
# A term with no TermProcessingStatus row was processed before the row
# existed, or only through POST /api/process_courses, which answers in its own
# response. For such a term, an enrollment means "processed".
class TermProcessingStatusSerializer
  NOT_STARTED = "not_started"

  def initialize(status_row, enrolled:)
    @status_row = status_row
    @enrolled = enrolled
  end

  def as_json(*)
    status = @status_row&.status || (@enrolled ? "processed" : NOT_STARTED)

    {
      processed:  status == "processed",
      status:     status,
      error_code: @status_row&.error_code
    }
  end
end
