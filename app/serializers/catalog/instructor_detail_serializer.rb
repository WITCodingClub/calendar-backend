# frozen_string_literal: true

module Catalog
  # One instructor with everything WIT Calendar knows from Rate My Professors:
  # the summary (InstructorSerializer), the rating distribution, the top tags,
  # and the newest reviews with a comment. Pass a term to add the sections the
  # instructor teaches in it.
  #
  # GET /api/v1/catalog/instructors/:pub_id and the get_instructor MCP tool
  # return it. The data comes from the nightly Rate My Professors sync; this
  # serializer never calls Rate My Professors.
  class InstructorDetailSerializer
    RECENT_REVIEWS = 5
    TOP_TAGS       = 10

    def initialize(faculty, term: nil)
      @faculty = faculty
      @term    = term
    end

    def as_json(*)
      return nil if @faculty.nil?

      json = InstructorSerializer.new(@faculty).as_json.merge(
        rating_distribution: rating_distribution,
        rmp_tags:            @faculty.teacher_rating_tags.top_tags(TOP_TAGS).map { |tag| { name: tag.tag_name, count: tag.tag_count } },
        recent_reviews:      recent_reviews,
        review_count:        @faculty.rmp_ratings.where.not(comment: [ nil, "" ]).count,
        reviews_source:      ReviewSerializer::SOURCE
      )
      json[:sections] = sections if @term
      json
    end

    private

    # How many ratings gave each score, 1 (awful) to 5 (awesome).
    def rating_distribution
      distribution = @faculty.rating_distribution
      return nil if distribution.nil? || distribution.total.to_i.zero?

      { "1" => distribution.r1, "2" => distribution.r2, "3" => distribution.r3, "4" => distribution.r4, "5" => distribution.r5 }
    end

    def recent_reviews
      ratings = ReviewQuery.with_associations(ReviewQuery.new.call(instructor: @faculty.public_id)).limit(RECENT_REVIEWS)
      ratings.map { |rating| ReviewSerializer.new(rating).as_json.except(:instructor) }
    end

    def sections
      relation = SectionQuery.with_associations(
        SectionQuery.new(@faculty.courses).call(term_uid: @term.uid)
      ).to_a
      catalog_courses = CourseQuery.for_sections(relation)
      relation.map { |section| SectionSerializer.new(section, catalog_courses: catalog_courses).as_json }
    end
  end
end
