# frozen_string_literal: true

module Catalog
  # Filters Rate My Professors reviews for the public catalog API, the MCP
  # tools, and the admin pages.
  #
  # Only reviews that carry a comment are offered. A row with ratings and no
  # words says nothing a reader can search.
  class ReviewQuery
    extend Filters

    SENTIMENTS = %w[positive negative].freeze

    filter :instructor, :string, "Only reviews of this instructor: the pub_id from the instructors list, not a name.",
           mcp: :instructor_id
    filter :q, :string, "Words to find in the comment or the course."
    filter :semantic, :flag, "Rank q by meaning instead of by the literal words. A request can run one semantic search."
    filter :sentiment, :enum, "Positive or negative reviews only.", values: SENTIMENTS

    DEFAULT_ORDER = { rating_date: :desc, id: :desc }.freeze

    def initialize(scope = RmpRating.all)
      @scope = scope
    end

    def call(**filters)
      self.class.check_filters!(filters)

      relation = @scope.where.not(comment: [ nil, "" ])
      relation = apply_instructor(relation, filters[:instructor])
      relation = apply_sentiment(relation, filters[:sentiment])

      apply_text(relation, filters[:q], semantic: Params.boolean(filters[:semantic]))
    end

    def self.with_associations(relation)
      relation.includes(:faculty)
    end

    private

    # The instructor is named by public id, the same id the instructors
    # endpoint returns.
    def apply_instructor(relation, pub_id)
      return relation if pub_id.blank?

      faculty = Faculty.find_by_public_id(pub_id.to_s.strip)
      raise FilterError, "Unknown instructor #{pub_id.inspect}" if faculty.nil?

      relation.where(faculty_id: faculty.id)
    end

    def apply_sentiment(relation, sentiment)
      return relation if sentiment.blank?

      key = sentiment.to_s.downcase
      raise FilterError, "Unknown sentiment #{sentiment.inspect}" unless SENTIMENTS.include?(key)

      key == "positive" ? relation.positive : relation.negative
    end

    def apply_text(relation, query, semantic:)
      return relation.order(DEFAULT_ORDER) if query.blank?

      ranked = semantic ? SemanticSearch.ranked_scope(relation, query) : nil
      return ranked if ranked

      term = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)}%"
      relation.where("rmp_ratings.comment ILIKE :q OR rmp_ratings.course_name ILIKE :q", q: term)
              .order(DEFAULT_ORDER)
    end
  end
end
