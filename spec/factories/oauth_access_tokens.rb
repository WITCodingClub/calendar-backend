# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_access_token, class: "Doorkeeper::AccessToken" do
    # Doorkeeper validates the ids, so build() needs saved records too.
    association :application, factory: :oauth_application, strategy: :create
    resource_owner_id { create(:user).id }
    expires_in { 1.hour.to_i }
    scopes { "read" }

    trait :expired do
      created_at { 2.hours.ago }
    end

    trait :revoked do
      revoked_at { 1.minute.ago }
    end
  end
end
