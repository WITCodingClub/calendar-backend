# frozen_string_literal: true

class UpdateFacultyRatingsJob < ApplicationJob
  queue_as :low

  def perform(faculty_id)
    faculty = Faculty.find(faculty_id)
    service = RateMyProfessorService.new

    # If faculty doesn't have an rmp_id, search for them first
    if faculty.rmp_id.blank?
      search_and_link_faculty(faculty, service)
      return if faculty.rmp_id.blank?
    end

    # Fetch teacher details and all ratings
    fetch_and_store_ratings(faculty, service)
  end

  private

  def search_and_link_faculty(faculty, service)
    search_result = service.search_professors(faculty.full_name, count: 10)
    teachers = search_result.dig("data", "newSearch", "teachers", "edges") || []

    # Find match where both first and last name match
    best_match = teachers.find do |edge|
      teacher = edge["node"]
      first_name_match = teacher["firstName"]&.downcase&.strip == faculty.first_name&.downcase&.strip
      last_name_match = teacher["lastName"]&.downcase&.strip == faculty.last_name&.downcase&.strip
      first_name_match && last_name_match
    end&.dig("node")

    return unless best_match

    faculty.update(rmp_id: best_match["id"])
  end

  def fetch_and_store_ratings(faculty, service)
    teacher_data = service.get_teacher_details(faculty.rmp_id)
    teacher = teacher_data.dig("data", "node")

    return unless teacher

    # Fetch all ratings
    all_ratings = service.get_all_ratings(faculty.rmp_id)

    # Store the raw GraphQL response for graph reconstruction
    store_raw_data(faculty, teacher_data, all_ratings)

    # Store rating distribution and aggregate stats
    store_rating_distribution(faculty, teacher["ratingsDistribution"], teacher)

    # Store teacher rating tags
    store_teacher_rating_tags(faculty, teacher["teacherRatingTags"] || [])

    # Store related professors
    store_related_professors(faculty, teacher["relatedTeachers"] || [])

    # Store individual ratings
    store_ratings(faculty, all_ratings)

    Rails.logger.info "Updated #{all_ratings.count} ratings for #{faculty.full_name}"
  end

  def store_related_professors(faculty, related_teachers)
    related_teachers.each do |related|
      related_prof = faculty.related_professors.find_or_initialize_by(
        rmp_id: related["id"]
      )

      related_prof.assign_attributes(
        first_name: related["firstName"],
        last_name: related["lastName"],
        avg_rating: related["avgRating"]
      )

      related_prof.save!

      # Try to match to existing faculty
      related_prof.try_match_faculty!
    end
  end

  def store_ratings(faculty, ratings)
    ratings.each do |rating|
      rmp_rating = faculty.rmp_ratings.find_or_initialize_by(
        rmp_id: rating["legacyId"].to_s
      )

      rmp_rating.assign_attributes(
        clarity_rating: rating["clarityRating"],
        difficulty_rating: rating["difficultyRating"],
        helpful_rating: rating["helpfulRating"],
        course_name: rating["class"],
        comment: rating["comment"],
        rating_date: parse_date(rating["date"]),
        grade: rating["grade"],
        would_take_again: parse_would_take_again(rating["wouldTakeAgain"]),
        attendance_mandatory: rating["attendanceMandatory"],
        is_for_credit: rating["isForCredit"],
        is_for_online_class: rating["isForOnlineClass"],
        rating_tags: rating["ratingTags"],
        thumbs_up_total: rating["thumbsUpTotal"] || 0,
        thumbs_down_total: rating["thumbsDownTotal"] || 0
      )

      rmp_rating.save!
    end
  end

  def store_rating_distribution(faculty, distribution_data, teacher_data)
    return unless distribution_data

    rating_dist = faculty.rating_distribution || faculty.build_rating_distribution

    rating_dist.assign_attributes(
      r1: distribution_data["r1"] || 0,
      r2: distribution_data["r2"] || 0,
      r3: distribution_data["r3"] || 0,
      r4: distribution_data["r4"] || 0,
      r5: distribution_data["r5"] || 0,
      total: distribution_data["total"] || 0,
      avg_rating: teacher_data["avgRating"],
      avg_difficulty: teacher_data["avgDifficulty"],
      num_ratings: teacher_data["numRatings"],
      would_take_again_percent: teacher_data["wouldTakeAgainPercent"]
    )

    rating_dist.save!
  end

  def store_teacher_rating_tags(faculty, tags_data)
    tags_data.each do |tag|
      rating_tag = faculty.teacher_rating_tags.find_or_initialize_by(
        rmp_legacy_id: tag["legacyId"]
      )

      rating_tag.assign_attributes(
        tag_name: tag["tagName"],
        tag_count: tag["tagCount"] || 0
      )

      rating_tag.save!
    end
  end

  def store_raw_data(faculty, teacher_data, all_ratings)
    raw_data = {
      teacher: teacher_data,
      all_ratings: all_ratings,
      metadata: {
        last_updated_at: Time.current.iso8601,
        total_ratings_fetched: all_ratings.count
      }
    }

    faculty.update!(rmp_raw_data: raw_data)
  end

  def parse_date(date_string)
    return nil if date_string.blank?

    DateTime.parse(date_string)
  rescue ArgumentError
    nil
  end

  def parse_would_take_again(value)
    case value
    when true, "Yes", 1
      true
    when false, "No", 0
      false
    else
      nil
    end
  end

end
