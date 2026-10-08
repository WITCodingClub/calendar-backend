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
module Brightspace
  class Announcement < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    include Brightspace::Removable

    set_public_id_prefix :ban, min_hash_length: 12

    belongs_to :course_offering, class_name: "Brightspace::CourseOffering", inverse_of: :announcements

    validates :source_id, presence: true, length: { maximum: 64 }, uniqueness: { scope: :course_offering_id }
    validates :title, presence: true, length: { maximum: 500 }
  end
end
