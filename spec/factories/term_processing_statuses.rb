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
FactoryBot.define do
  factory :term_processing_status do
    association :user
    association :term
    status { "pending" }

    trait :failed do
      status { "failed" }
      error_code { TermProcessingStatus::ERROR_CODES[:banner_unavailable] }
    end
  end
end
