# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_announcements
#
#  id                 :bigint           not null, primary key
#  body               :text
#  posted_at          :datetime
#  removed_at         :datetime
#  source_url         :string
#  title              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_announcements_on_course_offering_id  (course_offering_id)
#  index_brightspace_announcements_on_source              (course_offering_id,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
FactoryBot.define do
  factory :brightspace_announcement, class: "Brightspace::Announcement" do
    association :course_offering, factory: :brightspace_course_offering
    sequence(:source_id) { |n| (70_000 + n).to_s }
    title { Faker::Lorem.sentence(word_count: 4) }
    posted_at { 1.day.ago.change(usec: 0) }
  end
end
