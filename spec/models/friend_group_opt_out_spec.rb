# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe FriendGroupOptOut, type: :model do
  subject { create(:friend_group_opt_out) }

  it { is_expected.to belong_to(:friend_group) }
  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:friend_group_id) }
end
