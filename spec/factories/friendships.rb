# frozen_string_literal: true

# == Schema Information
#
# Table name: friendships
#
#  id                   :bigint           not null, primary key
#  addressee_visibility :integer          default(0), not null
#  expires_at           :datetime
#  proposed_expires_at  :datetime
#  proposed_permanent   :boolean          default(FALSE), not null
#  requester_visibility :integer          default(0), not null
#  status               :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  addressee_id         :bigint           not null
#  proposed_by_id       :bigint
#  requester_id         :bigint           not null
#
# Indexes
#
#  index_friendships_on_addressee_id_and_status        (addressee_id,status)
#  index_friendships_on_expires_at                     (expires_at) WHERE (expires_at IS NOT NULL)
#  index_friendships_on_proposed_by_id                 (proposed_by_id)
#  index_friendships_on_requester_id_and_addressee_id  (requester_id,addressee_id) UNIQUE
#  index_friendships_on_requester_id_and_status        (requester_id,status)
#  index_friendships_on_unordered_pair                 (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (addressee_id => users.id)
#  fk_rails_...  (proposed_by_id => users.id)
#  fk_rails_...  (requester_id => users.id)
#
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

    # The model refuses an expiry date in the past, so a spec that needs an
    # expired friendship creates a temporary one and travels past the date.
    trait :temporary do
      expires_at { 1.week.from_now }
    end

    # The requester proposed a later end date that the addressee has not
    # answered yet.
    trait :expiry_proposal do
      temporary
      proposed_by { requester }
      proposed_expires_at { 30.days.from_now }
    end
  end
end
