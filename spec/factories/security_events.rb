# frozen_string_literal: true

FactoryBot.define do
  factory :security_event do
    sequence(:jti) { |n| "factory-jti-#{n}" }
    event_type { SecurityEvent::VERIFICATION }
    google_subject { "factory-subject" }
  end
end
