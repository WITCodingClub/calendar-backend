# frozen_string_literal: true

# == Schema Information
#
# Table name: course_plans
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  notes                 :text
#  planned_course_number :integer          not null
#  planned_crn           :integer
#  planned_subject       :string           not null
#  status                :string           default("planned"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint
#  term_id               :bigint           not null
#  user_id               :bigint           not null
#
# Indexes
#
#  index_course_plans_on_course_id              (course_id)
#  index_course_plans_on_status                 (status)
#  index_course_plans_on_term_id                (term_id)
#  index_course_plans_on_user_id                (user_id)
#  index_course_plans_on_user_id_and_course_id  (user_id,course_id) UNIQUE WHERE (course_id IS NOT NULL)
#  index_course_plans_on_user_id_and_term_id    (user_id,term_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
class CoursePlanSerializer
  def initialize(plan)
    @plan = plan
  end

  def as_json(*)
    {
      id: @plan.id,
      term: TermSerializer.new(@plan.term).as_json,
      subject: @plan.planned_subject,
      course_number: @plan.planned_course_number,
      crn: @plan.planned_crn,
      course_identifier: @plan.course_identifier,
      status: @plan.status,
      notes: @plan.notes,
      course_id: @plan.course_id,
      created_at: @plan.created_at,
      updated_at: @plan.updated_at
    }
  end

end
