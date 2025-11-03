# == Schema Information
#
# Table name: rating_distributions
# Database name: primary
#
#  id         :bigint           not null, primary key
#  r1         :integer          default(0)
#  r2         :integer          default(0)
#  r3         :integer          default(0)
#  r4         :integer          default(0)
#  r5         :integer          default(0)
#  total      :integer          default(0)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  faculty_id :bigint           not null
#
# Indexes
#
#  index_rating_distributions_on_faculty_id  (faculty_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
FactoryBot.define do
  factory :rating_distribution do
    faculty { nil }
    r1 { 1 }
    r2 { 1 }
    r3 { 1 }
    r4 { 1 }
    r5 { 1 }
    total { 1 }
  end
end
