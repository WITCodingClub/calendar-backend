# frozen_string_literal: true

# == Schema Information
#
# Table name: user_extension_configs
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  default_color_lab     :string           default("#fbd75b"), not null
#  default_color_lecture :string           default("#46d6db"), not null
#  military_time         :boolean          default(FALSE), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  user_id               :bigint           not null
#
# Indexes
#
#  index_user_extension_configs_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :user_extension_config do

  end
end
