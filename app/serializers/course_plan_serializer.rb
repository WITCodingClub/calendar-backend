# frozen_string_literal: true

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
