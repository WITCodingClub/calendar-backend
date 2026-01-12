# frozen_string_literal: true

# Policy for FinalsSchedule (admin-only resource for managing finals PDF uploads)
#
# Access levels:
# - index/show: admin+ can view uploads and results
# - create: super_admin+ can upload new PDFs
# - destroy: super_admin+ can delete schedules (and associated final exams)
class FinalsSchedulePolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin?
  end

  def create?
    super_admin?
  end

  def new?
    create?
  end

  def destroy?
    super_admin?
  end

  def confirm_replace?
    super_admin?
  end

  def process_schedule?
    super_admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin_access?
        scope.all
      else
        scope.none
      end
    end

  end

end
