# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_groups
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_friend_groups_on_user_id_and_lower_name  (user_id, lower((name)::text)) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :friend_group do
    user
    sequence(:name) { |n| "#{Faker::Lorem.word.capitalize} group #{n}" }

    # A group that already holds accepted friends of its owner.
    trait :with_members do
      transient do
        members_count { 2 }
      end

      after(:create) do |group, evaluator|
        create_list(:friend_group_membership, evaluator.members_count, friend_group: group)
      end
    end
  end
end
