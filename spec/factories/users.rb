# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  access_level              :integer          default("user"), not null
#  calendar_token            :string
#  email                     :string           default(""), not null
#  first_name                :string
#  google_access_token       :string
#  google_refresh_token      :string
#  google_token_expires_at   :datetime
#  google_uid                :string
#  last_name                 :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  google_course_calendar_id :string
#
# Indexes
#
#  index_users_on_calendar_token  (calendar_token) UNIQUE
#  index_users_on_email           (email) UNIQUE
#  index_users_on_google_uid      (google_uid)
#
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@wit.edu" }
    first_name { "Test" }
    last_name { "User" }
    access_level { :user }
  end
end
