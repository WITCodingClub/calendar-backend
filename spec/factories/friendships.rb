# frozen_string_literal: true

# == Schema Information
#
# Table name: friendships
# Database name: primary
#
#  id           :bigint           not null, primary key
#  status       :integer          default("pending"), not null
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
#
# Foreign Keys
#
#  fk_rails_...  (addressee_id => users.id)
#  fk_rails_...  (requester_id => users.id)
#
FactoryBot.define do
  factory :friendship do
    requester factory: %i[user]
    addressee factory: %i[user]
    status { :pending }

    trait :pending do
      status { :pending }
    end

    trait :accepted do
      status { :accepted }
    end
  end
end
