# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_access_token, class: "Doorkeeper::AccessToken" do
    # Doorkeeper validates the ids, so build() needs saved records too.
    association :application, factory: :oauth_application, strategy: :create
    resource_owner_id { create(:user).id }
    expires_in { 1.hour.to_i }
    scopes { McpTools::Scopes::LEGACY_READ_SCOPES.join(" ") }

    # A token issued before the scopes were split (McpTools::Scopes::LEGACY_READ).
    trait :legacy_read do
      scopes { "read" }
    end

    trait :all_scopes do
      scopes { McpTools::Scopes::NAMES.join(" ") }
    end

    trait :expired do
      created_at { 2.hours.ago }
    end

    trait :revoked do
      revoked_at { 1.minute.ago }
    end
  end
end
