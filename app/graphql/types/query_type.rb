# frozen_string_literal: true

module Types
  class QueryType < BaseObject
    description "Public, read-only WIT course catalog"

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

    def instructors(term_uid: nil, q: nil)
      scope = Faculty.where(id: Faculty.joins(:courses).select("faculties.id"))
                     .includes(:rating_distribution)

      if term_uid
        scope = scope.where(
          id: Faculty.joins(:courses)
                     .where(courses: { term_id: Term.where(uid: term_uid).select(:id) })
                     .select("faculties.id")
        )
      end

      if q.present?
        query = "%#{ActiveRecord::Base.sanitize_sql_like(q.strip)}%"
        scope = scope.where(
          "faculties.first_name ILIKE :q OR faculties.last_name ILIKE :q OR faculties.display_name ILIKE :q",
          q: query
        )
      end

      scope.order(:last_name, :first_name)
    end

    private

    def subject_code(subject)
      subject =~ /\(([^)]+)\)/ ? ::Regexp.last_match(1) : subject
    end
  end
end
