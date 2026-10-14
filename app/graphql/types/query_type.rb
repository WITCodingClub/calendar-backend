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

    field :course, CourseType, null: true,
          description: "One course by code, such as \"COMP 2350\", across terms" do
      argument :code, String, required: true
    end

    field :courses, CourseType.connection_type, null: false,
          description: "Courses (not sections) by code or title words" do
      argument :q, String, required: false
      argument :subject, [ String ], required: false, description: "Subject codes, e.g. [\"COMP\"]"
      argument :term_uid, Integer, required: false, description: "Only courses with a section in this term"
      directive Directives::ListSize, **CONNECTION_LIST_SIZE
    end

    field :instructors, InstructorType.connection_type, null: false,
          description: "Faculty who teach at least one section" do
      argument :term_uid, Integer, required: false
      argument :q, String, required: false, description: "Each word must match the first, last, or display name"
      argument :semantic, Boolean, required: false, default_value: false,
               description: "Rank q by meaning instead of by the literal name. " \
                            "A query can run one semantic search."
      directive Directives::ListSize, **CONNECTION_LIST_SIZE
    end

    field :reviews, ReviewType.connection_type, null: false,
          description: "Rate My Professors reviews of WIT instructors" do
      argument :instructor, String, required: false, description: "An instructor public id"
      argument :q, String, required: false, description: "Free text over the comment and the course"
      argument :semantic, Boolean, required: false, default_value: false,
               description: "Rank q by meaning instead of by the literal words. " \
                            "A query can run one semantic search."
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
      ::Catalog::SubjectQuery.new.call(term_uid: term_uid)
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

    def course(code:)
      ::Catalog::CourseQuery.new.find(code)
    end

    def courses(q: nil, subject: nil, term_uid: nil)
      ::Catalog::CourseQuery.new.call(q: q, subject: subject, term_uid: term_uid)
    end

    def instructors(term_uid: nil, q: nil, semantic: false)
      ::Catalog::InstructorQuery.new.call(term_uid: term_uid, q: q, semantic: semantic)
    end
  end
end
