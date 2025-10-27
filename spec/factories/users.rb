# == Schema Information
#
# Table name: users
#
#  id           :bigint           not null, primary key
#  access_level :integer          default("user"), not null
#  email        :string           default(""), not null
#  first_name   :string
#  last_name    :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_users_on_email  (email) UNIQUE
#
FactoryBot.define do
  factory :user do
    
  end
end
