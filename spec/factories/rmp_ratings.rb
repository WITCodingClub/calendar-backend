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
    faculty { nil }
    rmp_id { "MyString" }
    clarity_rating { 1 }
    difficulty_rating { 1 }
    helpful_rating { 1 }
    course_name { "MyString" }
    comment { "MyText" }
    rating_date { "2025-11-02 19:16:30" }
    grade { "MyString" }
    would_take_again { false }
    attendance_mandatory { "MyString" }
    is_for_credit { false }
    is_for_online_class { false }
    rating_tags { "MyText" }
    thumbs_up_total { 1 }
    thumbs_down_total { 1 }
  end
end
