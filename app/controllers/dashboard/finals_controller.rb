# frozen_string_literal: true

module Dashboard
  # The finals schedule of a term, read-only (#797). The user's own exams get a
  # badge, and mine=1 shows only them.
  class FinalsController < Dashboard::ApplicationController
    include CatalogPages

    def index
      authorize FinalExam

      @terms = Term.where(id: FinalExam.select(:term_id)).reverse_chronological.to_a
      @term  = selected_term(default: default_term)
      # Only a term with a finals schedule. Any other term has nothing to show.
      raise ActiveRecord::RecordNotFound, "No finals for term #{@term.uid}" if @term && @terms.exclude?(@term)

      @current_term = Term.current
      @query = params[:q].to_s.strip
      @mine  = params[:mine].to_s == "1"
      @my_course_ids   = Set.new
      @catalog_courses = {}

      if @term.nil?
        @exams = FinalExam.none.page(1)
        return
      end

      @my_course_ids = current_user.enrollments.where(term_id: @term.id).pluck(:course_id).to_set
      @published     = @term.finals_published?
      @exams = Catalog::FinalExamQuery.new.call(term: @term, q: @query, course_ids: (@my_course_ids.to_a if @mine))
                                      .page(page_param).per(50)
      # The catalog course of each section, so a row links to its page only
      # when the page exists.
      @catalog_courses = Catalog::CourseQuery.for_sections(@exams.filter_map(&:course))
    end

    private

    # The current term when it has exams, otherwise the newest term with exams.
    def default_term
      current = Term.current
      @terms.include?(current) ? current : @terms.first
    end
  end
end
