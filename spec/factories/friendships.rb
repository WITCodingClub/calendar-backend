# frozen_string_literal: true

# == Schema Information
#
# Table name: friendships
#
#  id           :bigint           not null, primary key
#  status       :integer          default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  addressee_id :bigint           not null
#  requester_id :bigint           not null
#
# Indexes
#
#  index_friendships_on_addressee_id                   (addressee_id)
#  index_friendships_on_addressee_id_and_status        (addressee_id,status)
#  index_friendships_on_requester_id                   (requester_id)
#  index_friendships_on_requester_id_and_addressee_id  (requester_id,addressee_id) UNIQUE
#  index_friendships_on_requester_id_and_status        (requester_id,status)
#  index_friendships_on_unordered_pair                 (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (addressee_id => users.id)
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
  end
end
