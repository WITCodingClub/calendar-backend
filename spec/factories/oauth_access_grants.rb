# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_access_grant, class: "Doorkeeper::AccessGrant" do
    # Doorkeeper validates the ids, so build() needs saved records too.
    association :application, factory: :oauth_application, strategy: :create
    resource_owner_id { create(:user).id }
    redirect_uri { application.redirect_uri.split.first }
    expires_in { 5.minutes.to_i }
    scopes { "read" }
  end
end
