# frozen_string_literal: true

# == Schema Information
#
# Table name: user_backfills
#
#  id           :bigint           not null, primary key
#  completed_at :datetime         not null
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_user_backfills_on_user_id_and_name  (user_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :user_backfill do
    user
    name { "past_terms" }
    completed_at { Time.current }
  end
end
