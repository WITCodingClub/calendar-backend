# == Schema Information
#
# Table name: faculties
#
#  id         :bigint           not null, primary key
#  email      :string           not null
#  first_name :string           not null
#  last_name  :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_faculties_on_email  (email) UNIQUE
#
FactoryBot.define do
  factory :faculty do
    
  end
end
