# frozen_string_literal: true

class CoursePolicy < PublicRecordPolicy
  def index? = admin?
  def show?  = admin?
end
