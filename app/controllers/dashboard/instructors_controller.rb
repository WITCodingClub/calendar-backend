# frozen_string_literal: true

module Dashboard
  # The instructors of the catalog, read-only (#797). It shows what
  # GET /api/v1/catalog/instructors returns, from the same query and
  # serializers. No email, phone, or office: the serializers leave them out.
  class InstructorsController < Dashboard::ApplicationController
    include CatalogPages

    def index
      authorize Faculty

      @query = params[:q].to_s.strip
      @term  = selected_term(default: nil)
      @terms = term_options
      people = Catalog::InstructorQuery.new.call(term_uid: @term&.uid, q: @query.presence)
                                       .page(page_param).per(CatalogPages::PER_PAGE)
      @page        = people
      @instructors = people.map { |faculty| Catalog::InstructorSerializer.new(faculty).as_json }
    end

    def show
      faculty = Faculty.includes(:rating_distribution).find_by_public_id(params[:id]) # rubocop:disable Rails/DynamicFindBy
      raise ActiveRecord::RecordNotFound, "No instructor #{params[:id]}" if faculty.nil?

      authorize faculty

      @offered_terms = Term.where(id: faculty.courses.active.select(:term_id)).reverse_chronological.to_a
      current        = Term.current
      @term          = selected_term(default: @offered_terms.include?(current) ? current : @offered_terms.first)
      @instructor    = Catalog::InstructorDetailSerializer.new(faculty, term: @term).as_json
      @rmp_url       = "https://www.ratemyprofessors.com/professor/#{faculty.rmp_numeric_id}" if faculty.rmp_id.present?
    end
  end
end
