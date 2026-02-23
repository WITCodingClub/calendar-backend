# frozen_string_literal: true

# Generates multi-semester course plan suggestions and validates existing plans.
#
# Usage:
#   service = CoursePlannerService.new(user)
#   suggestions = service.generate_plan(terms: [term1, term2])
#   # => { term1 => [course1, course2], term2 => [course3] }
#
#   validation = service.validate_plan(term: term)
#   # => { valid: true/false, issues: [...], warnings: [...] }
class CoursePlannerService
  MAX_CREDITS_PER_TERM = 18

  def initialize(user)
    @user = user
  end

  # Generate course suggestions for the given terms.
  # Returns a hash of { Term => [Course, ...] } without auto-saving.
  def generate_plan(terms:)
    unfulfilled = unfulfilled_requirements
    fulfilled_codes = completed_course_codes.dup
    planned_courses_by_term = {}

    terms.sort_by(&:start_date).each do |term|
      planned_credits = existing_credits_for_term(term)
      term_courses = []

      available_courses = Course.where(term: term, status: :active)
                                .where.not(credit_hours: nil)
                                .includes(:course_prerequisites, :meeting_times)

      unfulfilled.each do |req|
        break if planned_credits >= MAX_CREDITS_PER_TERM

        matching = find_matching_courses(available_courses, req, fulfilled_codes)

        matching.each do |course|
          break if planned_credits + (course.credit_hours || 0) > MAX_CREDITS_PER_TERM
          next if term_courses.any? { |c| c.id == course.id }
          next if schedule_conflict?(course, term_courses)
          next unless prerequisites_met?(course, fulfilled_codes)

          term_courses << course
          planned_credits += course.credit_hours || 0
          fulfilled_codes << "#{course.subject}#{course.course_number}"
          break # One course per requirement, move to next
        end
      end

      planned_courses_by_term[term] = term_courses
    end

    planned_courses_by_term
  end

  # Validate a user's existing course plan for a term.
  # Returns { valid:, issues:, warnings: }
  def validate_plan(term:)
    plans = @user.course_plans.active.by_term(term).includes(course: [:course_prerequisites, :meeting_times])
    issues = []
    warnings = []

    # Check credit hours
    total_credits = plans.joins(:course).sum("courses.credit_hours")
    if total_credits > MAX_CREDITS_PER_TERM
      issues << "Total credits (#{total_credits}) exceed maximum of #{MAX_CREDITS_PER_TERM}"
    elsif total_credits > 15
      warnings << "Heavy course load: #{total_credits} credits"
    end

    # Check prerequisites for each planned course
    plans.each do |plan|
      next unless plan.course

      result = PrerequisiteValidationService.call(user: @user, course: plan.course)
      unless result[:eligible]
        unmet = result[:requirements].reject { |r| r[:met] }.map { |r| r[:rule] }
        issues << "Prerequisites not met for #{plan.course_identifier}: #{unmet.join(', ')}"
      end
    end

    # Check schedule conflicts
    courses_with_meetings = plans.select(&:course).map(&:course).select { |c| c.meeting_times.any? }
    conflicts = find_schedule_conflicts(courses_with_meetings)
    conflicts.each do |conflict|
      issues << "Schedule conflict: #{conflict[:course_a]} and #{conflict[:course_b]} overlap on #{conflict[:day]}"
    end

    # Check requirement fulfillment
    linked_plans = plans.select(&:course)
    if linked_plans.empty? && plans.any?
      warnings << "No plans are linked to actual course sections yet"
    end

    {
      valid: issues.empty?,
      issues: issues,
      warnings: warnings,
      summary: {
        total_credits: total_credits,
        course_count: plans.size
      }
    }
  end

  private

  def completed_course_codes
    @completed_course_codes ||= @user.requirement_completions
                                     .where(in_progress: false)
                                     .pluck(:subject, :course_number)
                                     .map { |subject, number| "#{subject}#{number}" }
  end

  def unfulfilled_requirements
    user_programs = UserDegreeProgram.where(user: @user, status: :active)
    return [] if user_programs.empty?

    program_ids = user_programs.pluck(:degree_program_id)
    all_requirements = DegreeRequirement.where(degree_program_id: program_ids)
                                        .where.not(subject: nil)
                                        .where.not(course_number: nil)

    completed = completed_course_codes.to_set

    all_requirements.reject { |req| completed.include?("#{req.subject}#{req.course_number}") }
  end

  def existing_credits_for_term(term)
    CoursePlan.total_credits_for_term(@user, term)
  end

  def find_matching_courses(available_courses, requirement, fulfilled_codes)
    return [] unless requirement.subject && requirement.course_number

    available_courses.select do |course|
      course.subject&.include?(requirement.subject) &&
        course.course_number == requirement.course_number &&
        fulfilled_codes.exclude?("#{course.subject}#{course.course_number}")
    end
  end

  def prerequisites_met?(course, fulfilled_codes)
    return true if course.course_prerequisites.empty?

    # Simple check: see if all prerequisite course codes are in fulfilled list
    result = PrerequisiteValidationService.call(user: @user, course: course)
    result[:eligible]
  end

  def schedule_conflict?(new_course, existing_courses)
    new_meetings = new_course.meeting_times
    return false if new_meetings.empty?

    existing_courses.any? do |existing|
      existing.meeting_times.any? do |existing_mt|
        new_meetings.any? do |new_mt|
          times_overlap?(existing_mt, new_mt)
        end
      end
    end
  end

  def find_schedule_conflicts(courses)
    conflicts = []

    courses.combination(2).each do |course_a, course_b|
      course_a.meeting_times.each do |mt_a|
        course_b.meeting_times.each do |mt_b|
          next unless times_overlap?(mt_a, mt_b)

          conflicts << {
            course_a: "#{course_a.subject} #{course_a.course_number}",
            course_b: "#{course_b.subject} #{course_b.course_number}",
            day: mt_a.day_of_week
          }
        end
      end
    end

    conflicts.uniq { |c| [c[:course_a], c[:course_b], c[:day]] }
  end

  def times_overlap?(mt_a, mt_b)
    return false if mt_a.day_of_week != mt_b.day_of_week

    mt_a.begin_time < mt_b.end_time && mt_b.begin_time < mt_a.end_time
  end

end
