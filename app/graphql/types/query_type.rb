# frozen_string_literal: true

module Types
  class QueryType < BaseObject
    description "Public, read-only WIT course catalog"

    # IBM @listSize for a Relay connection. first or last sets the length of
    # edges and nodes. No page is ever longer than the maximum page size, so that
    # is the assumed size when a query gives neither.
    CONNECTION_LIST_SIZE = {
      slicing_arguments:            %w[first last],
      sized_fields:                 %w[edges nodes],
      assumed_size:                 ::Catalog::SectionQuery::MAX_PER_PAGE,
      require_one_slicing_argument: false
    }.freeze

    field :terms, [ TermType ], null: false,
          description: "All known terms, newest first"

    field :term, TermType, null: true,
          description: "One term by its Banner code" do
      argument :uid, Integer, required: true
    end

    field :subjects, [ SubjectType ], null: false,
          description: "Subjects offered, with section counts" do
      argument :term_uid, Integer, required: false
    end

    field :sections, SectionType.connection_type, null: false,
          description: "Course sections matching the given filters" do
      argument :filter, SectionFilterInput, required: false
      directive Directives::ListSize, **CONNECTION_LIST_SIZE
    end

    field :section, SectionType, null: true,
          description: "One section by CRN. Pass term_uid when a CRN repeats across terms." do
      argument :crn, Integer, required: true
      argument :term_uid, Integer, required: false
    end

    field :instructors, InstructorType.connection_type, null: false,
          description: "Faculty who teach at least one section" do
      argument :term_uid, Integer, required: false
      argument :q, String, required: false
      argument :semantic, Boolean, required: false, default_value: false,
               description: "Rank q by meaning instead of by the literal name"
      directive Directives::ListSize, **CONNECTION_LIST_SIZE
    end

    field :reviews, ReviewType.connection_type, null: false,
          description: "Rate My Professors reviews of WIT instructors" do
      argument :instructor, String, required: false, description: "An instructor public id"
      argument :q, String, required: false, description: "Free text over the comment and the course"
      argument :semantic, Boolean, required: false, default_value: false,
               description: "Rank q by meaning instead of by the literal words"
      argument :sentiment, String, required: false, description: "\"positive\" or \"negative\""
      directive Directives::ListSize, **CONNECTION_LIST_SIZE
    end

    def terms
      Term.reverse_chronological
    end

    def term(uid:)
      Term.find_by(uid: uid)
    end

    def subjects(term_uid: nil)
      scope = Course.active
      scope = scope.where(term_id: Term.where(uid: term_uid).select(:id)) if term_uid

      scope.group(:subject).count.sort_by { |subject, _| subject }.map do |subject, count|
        { subject: subject, code: subject_code(subject), section_count: count }
      end
    end

    def sections(filter: nil)
      filters  = filter ? filter.to_query_filters : {}
      relation = ::Catalog::SectionQuery.new.call(**filters)

      ::Catalog::SectionQuery.with_associations(relation)
    end

    def section(crn:, term_uid: nil)
      relation = ::Catalog::SectionQuery.new.call(
        crns:              [ crn ],
        term_uid:          term_uid,
        include_cancelled: true
      )

      ::Catalog::SectionQuery.with_associations(relation).first
    end

    def reviews(instructor: nil, q: nil, semantic: false, sentiment: nil)
      filters  = { instructor: instructor, q: q, semantic: semantic, sentiment: sentiment }.compact
      relation = ::Catalog::ReviewQuery.new.call(**filters)

      ::Catalog::ReviewQuery.with_associations(relation)
    end

    def instructors(term_uid: nil, q: nil, semantic: false)
      scope = Faculty.where(id: Faculty.joins(:courses).select("faculties.id"))
                     .includes(:rating_distribution)

      if term_uid
        scope = scope.where(
          id: Faculty.joins(:courses)
                     .where(courses: { term_id: Term.where(uid: term_uid).select(:id) })
                     .select("faculties.id")
        )
      end

      return scope.order(:last_name, :first_name) if q.blank?

      ranked = semantic ? ::Catalog::SemanticSearch.ranked_scope(scope, q) : nil
      return ranked if ranked

      query = "%#{ActiveRecord::Base.sanitize_sql_like(q.strip)}%"
      scope.where(
        "faculties.first_name ILIKE :q OR faculties.last_name ILIKE :q OR faculties.display_name ILIKE :q",
        q: query
      ).order(:last_name, :first_name)
    end

    private

    def subject_code(subject)
      subject =~ /\(([^)]+)\)/ ? ::Regexp.last_match(1) : subject
    end
  end
end
