# frozen_string_literal: true

# Response of GET /api/user/processed_events/status.
#
# "processed" stays a boolean for older extension versions. It is true only
# when the term is fully processed. "status" and "error_code" let the
# extension stop its poll when a term failed.
#
# A term with no TermProcessingStatus row was processed before the row
# existed, or only through POST /api/process_courses, which answers in its own
# response. For such a term, an enrollment means "processed".
# == Schema Information
#
# Table name: term_processing_statuses
#
#  id         :bigint           not null, primary key
#  error_code :string
#  status     :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  term_id    :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_term_processing_statuses_on_term_id              (term_id)
#  index_term_processing_statuses_on_user_id_and_term_id  (user_id,term_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
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
