# frozen_string_literal: true

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
# The processing state of one term for one user. POST /api/process_courses/batch
# writes it, and POST /api/user/is_processed reads it. A term is "processed"
# only after all of its courses are done, so the extension never sees a term
# that is half enrolled. A "failed" term has an error_code the extension can
# show.
class TermProcessingStatus < ApplicationRecord
  ERROR_CODES = {
    # The term does not exist in the database.
    term_not_found:    "term_not_found",
    # Banner answered with no details for every CRN in the term.
    no_course_details: "no_course_details",
    # Banner or the network failed on every retry.
    banner_unavailable: "banner_unavailable",
    # Any other error. The job is in the failed-jobs list.
    internal_error:    "internal_error"
  }.freeze

  belongs_to :user
  belongs_to :term

  enum :status, {
    pending:    "pending",
    processing: "processing",
    processed:  "processed",
    failed:     "failed"
  }, validate: true

  validates :error_code, inclusion: { in: ERROR_CODES.values }, allow_nil: true
  validates :term_id, uniqueness: { scope: :user_id }

  # Sets the state of one term for one user and clears an old error code.
  # One upsert, so two writers for the same term never collide on the unique
  # index.
  def self.record!(user, term, status, error_code: nil)
    upsert(
      {
        user_id:    user.id,
        term_id:    term.id,
        status:     statuses.fetch(status.to_s),
        error_code: error_code && ERROR_CODES.fetch(error_code.to_sym)
      },
      unique_by: %i[user_id term_id]
    )
  end
end
