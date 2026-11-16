# frozen_string_literal: true

module Types
  class QueryType < BaseObject
    description "Public, read-only WIT course catalog"

    # IBM @listSize for a Relay connection of a catalog list. first or last
    # sets the length of edges and nodes. No page is ever longer than the
    # list's maximum page size (Catalog::Page), so that is the assumed size
    # when a query gives neither.
    CONNECTION_LIST_SIZE = ::Catalog::Page::GRAPHQL_SIZES.to_h do |list, sizes|
      [ list, { slicing_arguments: %w[first last], sized_fields: %w[edges nodes],
                assumed_size: sizes[:max], require_one_slicing_argument: false }.freeze ]
    end.freeze

    field :terms, [ TermType ], null: false,
          description: "All known terms, newest first"

    field :term, TermType, null: true,
          description: "One term by its Banner code" do
      argument :uid, Integer, required: true
    end

    field :schedule_check, ScheduleCheckType, null: false,
          description: "Checks a set of sections taken together: time conflicts, linked " \
                       "lecture and lab pairs, the same course twice, and totals" do
      argument :term_uid, Integer, required: true
      argument :crns, [ Integer ], required: true,
               description: "At most #{::Catalog::ScheduleCheck::MAX_CRNS}"
    end

    field :subjects, [ SubjectType ], null: false,
          description: "Subjects offered, with section counts" do
      argument :term_uid, Integer, required: false
    end

    field :sections, SectionType.connection_type, null: false, max_page_size: ::Catalog::Page.max_size(:sections, surface: :graphql),
          description: "Course sections matching the given filters" do
      argument :filter, SectionFilterInput, required: false
      directive Directives::ListSize, **CONNECTION_LIST_SIZE[:sections]
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

    field :courses, CourseType.connection_type, null: false, max_page_size: ::Catalog::Page.max_size(:courses, surface: :graphql),
          description: "Courses (not sections) by code or title words" do
      CatalogFilterArguments.define(self, ::Catalog::CourseQuery)
      directive Directives::ListSize, **CONNECTION_LIST_SIZE[:courses]
    end

    field :instructors, InstructorType.connection_type, null: false, max_page_size: ::Catalog::Page.max_size(:instructors, surface: :graphql),
          description: "Faculty who teach at least one section" do
      CatalogFilterArguments.define(self, ::Catalog::InstructorQuery)
      directive Directives::ListSize, **CONNECTION_LIST_SIZE[:instructors]
    end

    field :reviews, ReviewType.connection_type, null: false, max_page_size: ::Catalog::Page.max_size(:reviews, surface: :graphql),
          description: "Rate My Professors reviews of WIT instructors" do
      CatalogFilterArguments.define(self, ::Catalog::ReviewQuery)
      directive Directives::ListSize, **CONNECTION_LIST_SIZE[:reviews]
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

    def schedule_check(term_uid:, crns:)
      ::Catalog::ScheduleCheck.new(term_uid: term_uid, crns: crns).call
    end

    def sections(filter: nil)
      ::Catalog::ListRequest.scope(:sections, filter.to_h.compact)
    end

    def section(crn:, term_uid: nil)
      ::Catalog::SectionQuery.find(crn, term_uid)
    end

    def reviews(**filters)
      ::Catalog::ListRequest.scope(:reviews, filters)
    end

    def course(code:)
      ::Catalog::CourseQuery.new.find(code)
    end

    def courses(**filters)
      ::Catalog::ListRequest.scope(:courses, filters)
    end

    def instructors(**filters)
      ::Catalog::ListRequest.scope(:instructors, filters)
    end
  end
end
