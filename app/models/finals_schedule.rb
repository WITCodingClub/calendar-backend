# frozen_string_literal: true

# == Schema Information
#
# Table name: finals_schedules
#
#  id             :bigint           not null, primary key
#  error_message  :text
#  processed_at   :datetime
#  stats          :jsonb
#  status         :integer          default("pending"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint           not null
#  uploaded_by_id :bigint           not null
#
# Indexes
#
#  index_finals_schedules_on_term_id                 (term_id)
#  index_finals_schedules_on_term_id_and_created_at  (term_id,created_at)
#  index_finals_schedules_on_uploaded_by_id          (uploaded_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (uploaded_by_id => users.id)
#
class FinalsSchedule < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  belongs_to :term
  belongs_to :uploaded_by, class_name: "User"

  has_one_attached :pdf_file

  enum :status, {
    pending:    0,
    processing: 1,
    completed:  2,
    failed:     3
  }, default: :pending

  validates :term,        presence: true
  validates :uploaded_by, presence: true
  validate  :pdf_file_is_pdf, if: -> { pdf_file.attached? }

  scope :recent,    -> { order(created_at: :desc) }
  scope :for_term,  ->(term) { where(term: term) }

  def trigger_calendar_resyncs_for_term
    users_to_sync = User
      .joins(oauth_credentials: :google_calendar)
      .joins(enrollments: :course)
      .where(courses: { term_id: term_id })
      .where(oauth_credentials: { provider: "google" })
      .distinct

    users_to_sync.find_each { |user| GoogleCalendarSyncJob.perform_later(user, force: true) }

    Rails.logger.info({
      message:   "Queued calendar re-sync after finals schedule import",
      term:      term.uid,
      user_count: users_to_sync.count
    }.to_json)
  end

  private

  def pdf_file_is_pdf
    errors.add(:pdf_file, "must be a PDF") unless pdf_file.content_type == "application/pdf"
  end
end
