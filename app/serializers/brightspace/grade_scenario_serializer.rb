# frozen_string_literal: true

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
  class GradeScenarioSerializer
    def initialize(scenario)
      @scenario = scenario
    end

    def as_json(*)
      {
        id:                 @scenario.public_id,
        class_id:           @scenario.course_offering.public_id,
        name:               @scenario.name,
        scores:             @scenario.scores,
        category_overrides: @scenario.category_overrides,
        updated_at:         @scenario.updated_at&.utc&.iso8601
      }
    end
  end
end
