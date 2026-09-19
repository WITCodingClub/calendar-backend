# frozen_string_literal: true

# == Schema Information
#
# Table name: teacher_rating_tags
#
#  id            :bigint           not null, primary key
#  tag_count     :integer          default(0)
#  tag_name      :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  faculty_id    :bigint           not null
#  rmp_legacy_id :integer          not null
#
# Indexes
#
#  index_teacher_rating_tags_on_faculty_id                    (faculty_id)
#  index_teacher_rating_tags_on_faculty_id_and_rmp_legacy_id  (faculty_id,rmp_legacy_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
FactoryBot.define do
  factory :teacher_rating_tag do
    association :faculty
    sequence(:rmp_legacy_id) { |n| n }
    tag_name { "Factory Tag" }
    tag_count { 0 }
  end
end
