# frozen_string_literal: true

# One RegistrationPlan, for /api/user/registration_plans (#995). as_json is
# the full plan, with a fresh schedule check when the caller passes one.
# summary is one row of the list, without the courses and the check.
# == Schema Information
#
# Table name: registration_plans
#
#  id          :bigint           not null, primary key
#  courses     :jsonb            not null
#  preferences :jsonb            not null
#  term_uid    :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_registration_plans_on_term_uid              (term_uid)
#  index_registration_plans_on_user_id_and_term_uid  (user_id,term_uid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (term_uid => terms.uid) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class RegistrationPlanSerializer
  def initialize(plan)
    @plan = plan
  end

  def as_json(schedule_check: nil)
    json = {
      term:        term_json,
      courses:     @plan.courses,
      preferences: @plan.preferences,
      crns:        @plan.crns,
      updated_at:  @plan.updated_at&.utc&.iso8601
    }
    schedule_check ? json.merge(schedule_check: schedule_check) : json
  end

  def summary
    {
      term:         term_json,
      crns:         @plan.crns,
      course_count: @plan.course_count,
      updated_at:   @plan.updated_at&.utc&.iso8601
    }
  end

  private

  def term_json
    { uid: @plan.term_uid, name: @plan.term&.name }
  end
end
