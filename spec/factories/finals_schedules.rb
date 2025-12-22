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
FactoryBot.define do
  factory :finals_schedule do
    term
    association :uploaded_by, factory: :user, access_level: :super_admin
    status { :pending }
    processed_at { nil }
    error_message { nil }
    stats { nil }

    after(:build) do |finals_schedule|
      finals_schedule.pdf_file.attach(
        io: StringIO.new("%PDF-1.4\ntest pdf content"),
        filename: "finals_schedule.pdf",
        content_type: "application/pdf"
      )
    end

    trait :processing do
      status { :processing }
    end

    trait :completed do
      status { :completed }
      processed_at { Time.current }
      stats { { total: 10, created: 8, updated: 1, skipped: 1 } }
    end

    trait :failed do
      status { :failed }
      processed_at { Time.current }
      error_message { "Failed to parse PDF: invalid format" }
    end
  end
end
