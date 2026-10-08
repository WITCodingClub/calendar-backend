# frozen_string_literal: true

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
