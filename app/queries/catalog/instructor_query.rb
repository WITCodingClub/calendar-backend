# frozen_string_literal: true

module Catalog
  # Finds the instructors of the public catalog: the faculty who teach at least
  # one section. The REST controller, the GraphQL schema, and the MCP server
  # use this object, so the three search alike.
  #
  # A name search matches every word of q against the first, last, or display
  # name, so "ada lovelace" finds Ada Lovelace. semantic: true ranks q by
  # meaning instead, and falls back to the name match when the embeddings API
  # cannot answer.
  class InstructorQuery
    def initialize(scope = Faculty.all)
      @scope = scope
    end

    # @return [ActiveRecord::Relation<Faculty>]
    def call(term_uid: nil, q: nil, semantic: false)
      # Subquery rather than joins(:courses): a join would multiply rows by
      # section count and break both the page size and the total.
      relation = @scope.where(id: Faculty.joins(:courses).select("faculties.id")).includes(:rating_distribution)
      relation = relation.where(id: teaching_in(term_uid)) if term_uid.present?
      return relation.order(:last_name, :first_name) if q.blank?

      ranked = semantic ? SemanticSearch.ranked_scope(relation, q) : nil
      return ranked if ranked

      name_match(relation, q).order(:last_name, :first_name)
    end

    private

    def teaching_in(term_uid)
      Faculty.joins(:courses)
             .where(courses: { term_id: Term.where(uid: term_uid.to_i).select(:id) })
             .select("faculties.id")
    end

    def name_match(relation, query)
      query.to_s.split.reduce(relation) do |scope, word|
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(word)}%"
        scope.where(
          "faculties.first_name ILIKE :q OR faculties.last_name ILIKE :q OR faculties.display_name ILIKE :q",
          q: pattern
        )
      end
    end
  end
end
