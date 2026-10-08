# frozen_string_literal: true

# A gradebook category with the rules that Brightspace reports for it. A nil
# rule is unknown, not zero.
# == Schema Information
#
# Table name: brightspace_grade_categories
#
#  id                 :bigint           not null, primary key
#  drop_highest       :integer
#  drop_lowest        :integer
#  extra_credit       :boolean
#  name               :string           not null
#  removed_at         :datetime
#  weight             :decimal(8, 4)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_grade_categories_on_course_offering_id  (course_offering_id)
#  index_brightspace_grade_categories_on_source              (course_offering_id,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
module Brightspace
  class GradeCategory < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    include Brightspace::Removable

    set_public_id_prefix :bgc, min_hash_length: 12

    belongs_to :course_offering, class_name: "Brightspace::CourseOffering", inverse_of: :grade_categories
    has_many :grade_items, class_name: "Brightspace::GradeItem", dependent: :nullify, inverse_of: :grade_category

    validates :source_id, presence: true, length: { maximum: 64 }, uniqueness: { scope: :course_offering_id }
    validates :name, presence: true, length: { maximum: 500 }
    validates :weight, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :drop_lowest, :drop_highest, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  end
end
