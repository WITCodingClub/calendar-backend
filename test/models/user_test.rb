# == Schema Information
#
# Table name: users
#
#  id                           :bigint           not null, primary key
#  access_level                 :integer          default("user"), not null
#  calendar_needs_sync          :boolean          default(FALSE), not null
#  calendar_token               :string
#  confirmation_sent_at         :datetime
#  confirmation_token           :string
#  confirmed_at                 :datetime
#  current_sign_in_at           :datetime
#  current_sign_in_ip           :string
#  email                        :string           default(""), not null
#  encrypted_password           :string           default(""), not null
#  failed_attempts              :integer          default(0), not null
#  first_name                   :string
#  last_calendar_sync_at        :datetime
#  last_name                    :string
#  last_sign_in_at              :datetime
#  last_sign_in_ip              :string
#  locked_at                    :datetime
#  notifications_disabled_until :datetime
#  remember_created_at          :datetime
#  reset_password_sent_at       :datetime
#  reset_password_token         :string
#  sign_in_count                :integer          default(0), not null
#  unconfirmed_email            :string
#  unlock_token                 :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_users_on_access_level           (access_level)
#  index_users_on_calendar_needs_sync    (calendar_needs_sync)
#  index_users_on_calendar_token         (calendar_token) UNIQUE
#  index_users_on_confirmation_token     (confirmation_token) UNIQUE
#  index_users_on_email                  (email) UNIQUE
#  index_users_on_last_calendar_sync_at  (last_calendar_sync_at)
#  index_users_on_reset_password_token   (reset_password_token) UNIQUE
#
require "test_helper"

class UserTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
