# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_group_opt_outs
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  friend_group_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_friend_group_opt_outs_on_friend_group_id_and_user_id  (friend_group_id,user_id) UNIQUE
#  index_friend_group_opt_outs_on_user_id                      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (friend_group_id => friend_groups.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :friend_group_opt_out do
    friend_group
    user
  end
end
