# frozen_string_literal: true

module Admin
  # Check or remove a course code alias from the review queue (#865).
  class CourseCodeAliasesController < Admin::ApplicationController
    def review
      course_code_alias = CourseCodeAlias.find(params[:id])
      authorize course_code_alias

      course_code_alias.update!(reviewed_at: Time.current)
      redirect_to admin_catalog_reviews_path(anchor: "aliases"),
                  notice: "Marked #{course_code_alias.from_code} to #{course_code_alias.to_code} as checked."
    end

    # A wrong alias is removed. `bin/rails degree_requirements:aliases`
    # adds it again only when a person runs that task again.
    def destroy
      course_code_alias = CourseCodeAlias.find(params[:id])
      authorize course_code_alias

      course_code_alias.destroy!
      redirect_to admin_catalog_reviews_path(anchor: "aliases"),
                  notice: "Removed #{course_code_alias.from_code} to #{course_code_alias.to_code}."
    end
  end
end
