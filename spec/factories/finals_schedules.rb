# frozen_string_literal: true

FactoryBot.define do
  factory :finals_schedule do
    association :term
    association :uploaded_by, factory: :user
  end
end
