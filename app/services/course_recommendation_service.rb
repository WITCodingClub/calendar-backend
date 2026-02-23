# frozen_string_literal: true

# Recommends courses for a user in a given term based on:
# - Unfulfilled degree requirements
# - Prerequisite eligibility
# - Courses not already planned or completed
#
# Usage:
#   result = CourseRecommendationService.call(user: user, term: term)
#   result[:recommendations] # => array of recommendation hashes
class CourseRecommendationService < ApplicationService
  def initialize(user:, term:)
    @user = user
    @term = term
    super()
  end

  def call
    available = available_courses
    available = exclude_already_planned(available)
    available = exclude_already_completed(available)

    recommendations = build_recommendations(available)
    recommendations = rank_recommendations(recommendations)

    {
      term: { uid: @term.uid, name: @term.name },
      recommendations: recommendations,
      total: recommendations.size
    }
  end

  private

  # All active courses offered in this term
  def available_courses
    Course.where(term: @term, status: :active)
          .includes(:faculties, :meeting_times, :course_prerequisites)
  end

  # Exclude courses already in the user's plan for this term
  def exclude_already_planned(courses)
    planned_course_ids = @user.course_plans
                              .where(term: @term)
                              .where(status: %w[planned enrolled])
                              .where.not(course_id: nil)
                              .pluck(:course_id)

    courses.where.not(id: planned_course_ids)
  end

  # Exclude courses the user has already completed with a passing grade
  def exclude_already_completed(courses)
    completed_pairs = completed_course_pairs
    return courses if completed_pairs.empty?

    # Build SQL conditions to exclude completed subject/course_number combos
    exclusion_conditions = completed_pairs.map do |subject, course_number|
      "(courses.subject = #{ActiveRecord::Base.connection.quote(subject)} AND courses.course_number = #{ActiveRecord::Base.connection.quote(course_number)})"
    end

    courses.where.not(exclusion_conditions.join(" OR "))
  end

  # Subject/course_number pairs the user has completed (from RequirementCompletion)
  def completed_course_pairs
    @completed_course_pairs ||= @user.requirement_completions
                                     .where(in_progress: false, met_requirement: true)
                                     .pluck(:subject, :course_number)
                                     .uniq
  end

  # Build recommendation entries with metadata
  def build_recommendations(courses)
    courses.filter_map do |course|
      prereq_result = PrerequisiteValidationService.call(user: @user, course: course)

      requirement_match = find_matching_requirement(course)
      priority = requirement_match ? "required" : "elective"

      {
        course: serialize_course(course),
        priority: priority,
        fulfills_requirement: requirement_match&.area_name,
        prerequisite_status: prereq_result[:eligible] ? "met" : "not_met",
        schedule_conflicts: has_schedule_conflicts?(course)
      }
    end
  end

  # Find an unfulfilled degree requirement that this course satisfies
  def find_matching_requirement(course)
    unfulfilled_requirements.find do |req|
      req.specific_course? &&
        req.subject == course.subject &&
        req.course_number == course.course_number
    end
  end

  # Degree requirements the user hasn't fulfilled yet
  def unfulfilled_requirements
    @unfulfilled_requirements ||= load_unfulfilled_requirements
  end

  def load_unfulfilled_requirements
    program_ids = UserDegreeProgram.where(user: @user, status: :active).pluck(:degree_program_id)
    return [] if program_ids.empty?

    all_requirements = DegreeRequirement.where(degree_program_id: program_ids)
                                        .where.not(subject: nil)
                                        .where.not(course_number: nil)

    # Filter out requirements already met
    met_requirement_ids = @user.requirement_completions
                               .where(met_requirement: true)
                               .pluck(:degree_requirement_id)
                               .to_set

    all_requirements.reject { |req| met_requirement_ids.include?(req.id) }
  end

  # Check if the course conflicts with the user's already-planned courses
  def has_schedule_conflicts?(course)
    planned_times = planned_meeting_times
    return false if planned_times.empty?

    course.meeting_times.any? do |mt|
      planned_times.any? do |pt|
        pt[:day] == mt.day_of_week &&
          times_overlap?(pt[:begin_time], pt[:end_time], mt.begin_time, mt.end_time)
      end
    end
  end

  # Meeting times from the user's already-planned courses in this term
  def planned_meeting_times
    @planned_meeting_times ||= begin
      planned_course_ids = @user.course_plans
                                .where(term: @term)
                                .where(status: %w[planned enrolled])
                                .where.not(course_id: nil)
                                .pluck(:course_id)

      MeetingTime.where(course_id: planned_course_ids).map do |mt|
        { day: mt.day_of_week, begin_time: mt.begin_time, end_time: mt.end_time }
      end
    end
  end

  def times_overlap?(start1, end1, start2, end2)
    return false if start1.nil? || end1.nil? || start2.nil? || end2.nil?

    start1 < end2 && start2 < end1
  end

  # Rank: required first, then electives. Within each: no conflicts first, then by RMP rating.
  def rank_recommendations(recommendations)
    recommendations.sort_by do |rec|
      priority_order = rec[:priority] == "required" ? 0 : 1
      conflict_order = rec[:schedule_conflicts] ? 1 : 0
      rmp_rating = avg_rating_for_course(rec[:course][:id]) || 0

      [priority_order, conflict_order, -rmp_rating]
    end
  end

  # Get average RMP rating for the first faculty teaching this course
  def avg_rating_for_course(course_id)
    @rating_cache ||= {}
    return @rating_cache[course_id] if @rating_cache.key?(course_id)

    course = Course.find_by(id: course_id)
    return @rating_cache[course_id] = nil unless course

    faculty = course.faculties.first
    return @rating_cache[course_id] = nil unless faculty

    @rating_cache[course_id] = faculty.rating_distribution&.avg_rating&.to_f
  end

  def serialize_course(course)
    faculty = course.faculties.first

    {
      id: course.id,
      subject: course.subject,
      course_number: course.course_number,
      title: course.title,
      crn: course.crn,
      credits: course.credit_hours,
      schedule_type: course.schedule_type,
      faculty: if faculty
                 {
                   name: faculty.full_name,
                   rmp_rating: faculty.rating_distribution&.avg_rating&.to_f
                 }
               end
    }
  end

end
