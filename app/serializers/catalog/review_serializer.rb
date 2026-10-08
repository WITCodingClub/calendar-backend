# frozen_string_literal: true

module Catalog
  # One Rate My Professors review as the public catalog API returns it.
  #
  # The text belongs to the student who wrote it on ratemyprofessors.com. The
  # payload names the source so a client can credit it and link back.
  class ReviewSerializer
    SOURCE = "ratemyprofessors.com"

    def initialize(rating)
      @rating = rating
    end

    def as_json(*)
      return nil if @rating.nil?

      {
        pub_id:            @rating.public_id,
        instructor:        instructor,
        course_name:       @rating.course_name,
        comment:           @rating.comment,
        clarity_rating:    @rating.clarity_rating,
        difficulty_rating: @rating.difficulty_rating,
        would_take_again:  @rating.would_take_again,
        sentiment:         @rating.overall_sentiment,
        tags:              tags,
        thumbs_up:         @rating.thumbs_up_total,
        thumbs_down:       @rating.thumbs_down_total,
        rated_on:          @rating.rating_date&.to_date,
        source:            SOURCE
      }
    end

    private

    def instructor
      faculty = @rating.faculty
      return nil if faculty.nil?

      { pub_id: faculty.public_id, name: faculty.full_name }
    end

    # Rate My Professors joins the tags of one review with "--".
    def tags
      @rating.rating_tags.to_s.split("--").map(&:strip).reject(&:empty?)
    end
  end
end
