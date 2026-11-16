# frozen_string_literal: true

module Dashboard
  # The course catalog, read-only (#797). It shows what
  # GET /api/v1/catalog/courses returns, from the same query and serializer.
  class CoursesController < Dashboard::ApplicationController
    include CatalogPages

    def index
      authorize CatalogCourse

      @query   = params[:q].to_s.strip
      @term    = selected_term
      @terms   = term_options
      @courses = Catalog::CourseQuery.new.call(q: @query.presence, term_uid: @term&.uid)
                                     .page(page_param).per(CatalogPages::PER_PAGE)
    end

    def show
      catalog_course = Catalog::CourseQuery.new.find(params[:code])
      raise ActiveRecord::RecordNotFound, "No course #{params[:code]}" if catalog_course.nil?

      authorize catalog_course

      @offered_terms = offered_terms(
        Catalog::SectionQuery.new.call(subject: [ catalog_course.subject_code ], course_number: [ catalog_course.course_number ])
      )
      @term   = selected_term(@offered_terms)
      @course = Catalog::CourseSerializer.new(catalog_course, term: @term).as_json
      @prerequisite_graph = Catalog::PrerequisiteGraph.new(catalog_course)
    end
  end
end
