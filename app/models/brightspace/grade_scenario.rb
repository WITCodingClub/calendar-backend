# frozen_string_literal: true

# A saved "what if": hypothetical points for grade items, and optional
# category rules. A scenario stores inputs only. It never replaces the
# imported grades, and the frontend does the calculation.
# == Schema Information
#
# Table name: brightspace_grade_scenarios
#
#  id                 :bigint           not null, primary key
#  category_overrides :jsonb
#  name               :string           not null
#  scores             :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_brightspace_grade_scenarios_on_course_offering_id  (course_offering_id)
#  index_brightspace_grade_scenarios_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#  fk_rails_...  (user_id => users.id)
#
module Brightspace
  class GradeScenario < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    include Brightspace::OwnedByClassUser
    include Brightspace::VersionBumping

    set_public_id_prefix :bgs, min_hash_length: 12

    MAX_SCORES = 500
    MAX_PER_CLASS = 50

    validates :name, presence: true, length: { maximum: 100 }
    validate :scores_format
    validate :category_overrides_format
    validate :class_limit, on: :create

    private

    # scores is [{ "item_id" => "bgi_...", "points" => 9.5 }]. A custom check:
    # the ids must be grade items of the same class.
    def scores_format
      return errors.add(:scores, "must be a list") unless scores.is_a?(Array)
      return errors.add(:scores, "has more than #{MAX_SCORES} entries") if scores.size > MAX_SCORES

      item_ids = course_offering ? course_offering.grade_items.map(&:public_id).to_set : Set.new
      scores.each_with_index do |score, index|
        unless score.is_a?(Hash) && (score.keys - %w[item_id points]).empty?
          errors.add(:scores, "item #{index} must be an object with item_id and points")
          next
        end

        errors.add(:scores, "item #{index} item_id is not a grade item of this class") unless item_ids.include?(score["item_id"])
        points = score["points"]
        errors.add(:scores, "item #{index} points must be a number of 0 or more") unless points.nil? || (points.is_a?(Numeric) && points >= 0)
      end

      ids = scores.grep(Hash).pluck("item_id")
      errors.add(:scores, "lists one item_id more than once") if ids.uniq.size != ids.size
    end

    def category_overrides_format
      Brightspace::GradeRules.errors_for(category_overrides, course_offering).each do |message|
        errors.add(:category_overrides, message)
      end
    end

    def class_limit
      return if course_offering.nil? || user.nil?
      return if self.class.where(user: user, course_offering: course_offering).count < MAX_PER_CLASS

      errors.add(:base, "A class can have at most #{MAX_PER_CLASS} scenarios")
    end
  end
end
