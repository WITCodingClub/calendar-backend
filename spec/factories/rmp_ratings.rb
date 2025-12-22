# frozen_string_literal: true

# == Schema Information
#
# Table name: rmp_ratings
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  attendance_mandatory :string
#  clarity_rating       :integer
#  comment              :text
#  course_name          :string
#  difficulty_rating    :integer
#  embedding            :vector(1536)
#  grade                :string
#  helpful_rating       :integer
#  is_for_credit        :boolean
#  is_for_online_class  :boolean
#  rating_date          :datetime
#  rating_tags          :text
#  thumbs_down_total    :integer          default(0)
#  thumbs_up_total      :integer          default(0)
#  would_take_again     :boolean
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  faculty_id           :bigint           not null
#  rmp_id               :string           not null
#
# Indexes
#
#  index_rmp_ratings_on_faculty_id  (faculty_id)
#  index_rmp_ratings_on_rmp_id      (rmp_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
FactoryBot.define do
  factory :rmp_rating do
    faculty
    sequence(:rmp_id) { |n| "rmp_#{n}" }
    clarity_rating { 4 }
    difficulty_rating { 3 }
    helpful_rating { 4 }
    course_name { "Introduction to Programming" }
    comment { "Great professor, explains concepts well." }
    rating_date { 1.month.ago }
    grade { "A" }
    would_take_again { true }
    attendance_mandatory { "No" }
    is_for_credit { true }
    is_for_online_class { false }
    rating_tags { "Gives good feedback,Respected" }
    thumbs_up_total { 10 }
    thumbs_down_total { 2 }
  end
end
