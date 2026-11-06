# frozen_string_literal: true

module Admin
  # The course code aliases (#865). An admin marks an alias as checked, and
  # a super admin deletes a wrong one. A deleted alias comes back unchecked
  # when the alias task runs again, and counts only after a new check.
  class CourseCodeAliasReviewsController < Admin::ApplicationController
    PER_PAGE = 100

    before_action :set_alias, only: [ :update, :destroy ]

    def index
      authorize CourseCodeAlias, policy_class: CourseCodeAliasReviewPolicy

      @reviewed = params[:status] == "reviewed"
      aliases = @reviewed ? CourseCodeAlias.reviewed.order(reviewed_at: :desc) : CourseCodeAlias.where(reviewed_at: nil)
      @aliases = aliases.order(:from_subject_code, :from_course_number, :to_course_number).page(params[:page]).per(PER_PAGE)
      @waiting = CourseCodeAlias.where(reviewed_at: nil).count
      @can_delete = CourseCodeAliasReviewPolicy.new(current_user, CourseCodeAlias).destroy?
    end

    def update
      authorize @alias, policy_class: CourseCodeAliasReviewPolicy

      @alias.update!(reviewed_at: Time.current)
      redirect_to admin_course_code_alias_reviews_path, notice: "Marked #{@alias.from_code} to #{@alias.to_code} as checked."
    end

    def destroy
      authorize @alias, policy_class: CourseCodeAliasReviewPolicy

      @alias.destroy!
      redirect_to admin_course_code_alias_reviews_path, notice: "Deleted #{@alias.from_code} to #{@alias.to_code}."
    end

    private

    def set_alias
      @alias = CourseCodeAlias.find(params[:id])
    end
  end
end
