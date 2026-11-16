# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_credits
#
#  id         :bigint           not null, primary key
#  code       :string           not null
#  credits    :integer
#  kind       :string
#  source     :string           not null
#  title      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_transfer_credits_on_user_id_and_code  (user_id,code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :transfer_credit do
    user
    sequence(:code) { |n| "ENGL #{1000 + (n % 9000)}" }
    title { Faker::Educator.course_name }
    credits { 4 }
    source { "transcript" }
    kind { "ap" }

    trait :student do
      source { "student" }
      kind { nil }
    end
  end
end
