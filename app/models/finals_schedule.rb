# frozen_string_literal: true

# == Schema Information
#
# Table name: finals_schedules
# Database name: primary
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
  belongs_to :term
  belongs_to :uploaded_by, class_name: "User"

  has_one_attached :pdf_file

  enum :status, {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }

  validates :pdf_file, presence: true
  validate :pdf_file_is_pdf

  scope :recent, -> { order(created_at: :desc) }
  scope :for_term, ->(term) { where(term: term) }

  # Process the uploaded PDF and create FinalExam records
  def process!
    update!(status: :processing)

    result = FinalsScheduleParserService.call(
      pdf_content: pdf_file.download,
      term: term
    )

    update!(
      status: :completed,
      processed_at: Time.current,
      stats: result.slice(:total, :created, :updated, :linked, :orphan, :rooms_created),
      error_message: (result[:errors].join("\n") if result[:errors].any?)
    )
  rescue => e
    update!(
      status: :failed,
      processed_at: Time.current,
      error_message: e.message
    )
    raise
  end

  private

  def pdf_file_is_pdf
    return unless pdf_file.attached?

    errors.add(:pdf_file, "must be a PDF") unless pdf_file.content_type == "application/pdf"
  end
end
