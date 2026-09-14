# frozen_string_literal: true

FactoryBot.define do
  factory :friendship do
    # cannot_friend_self compares the raw requester_id/addressee_id columns, so
    # both users need a real persisted id even when this factory is built (not
    # created) or the two unsaved (nil) ids compare equal.
    association :requester, factory: :user, strategy: :create
    association :addressee, factory: :user, strategy: :create

    trait :accepted do
      status { :accepted }
    end
  end
end
