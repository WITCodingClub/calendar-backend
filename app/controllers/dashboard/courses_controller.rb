# frozen_string_literal: true

module Dashboard
  # The course catalog, read-only (#797). It shows what
  # GET /api/v1/catalog/courses returns, from the same query and serializer.
  class CoursesController < Dashboard::ApplicationController
    include CatalogPages

    def index
      authorize CatalogCourse

      @query   = params[:q].to_s.strip
      @term    = selected_term(default: nil)
      @terms   = term_options
      @courses = Catalog::CourseQuery.new.call(q: @query.presence, term_uid: @term&.uid)
                                     .page(page_param).per(CatalogPages::PER_PAGE)
    end

    def show
      catalog_course = Catalog::CourseQuery.new.find(params[:code])
      raise ActiveRecord::RecordNotFound, "No course #{params[:code]}" if catalog_course.nil?

      authorize catalog_course

      @offered_terms = offered_terms(catalog_course)
      @term   = selected_term(default: default_term(@offered_terms))
      @course = Catalog::CourseSerializer.new(catalog_course, term: @term).as_json
      @prerequisite_graph = Catalog::PrerequisiteGraph.new(catalog_course)
    end

    private

    # The terms with a section of the course, newest first.
    def offered_terms(catalog_course)
      sections = Catalog::SectionQuery.new.call(subject: [ catalog_course.subject_code ], course_number: [ catalog_course.course_number ])
      Term.where(id: sections.reorder(nil).select(:term_id)).reverse_chronological.to_a
    end

    # The current term when the course has a section in it, otherwise the
    # newest term with a section. Nil when no term has one.
    def default_term(offered)
      current = Term.current
      offered.include?(current) ? current : offered.first
    end
  end
end
