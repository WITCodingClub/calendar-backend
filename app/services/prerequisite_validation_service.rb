# frozen_string_literal: true

# Validates whether a user meets the prerequisites for a given course.
#
# Returns a hash with:
#   eligible: true/false
#   requirements: array of per-prerequisite result hashes
#
# Usage:
#   result = PrerequisiteValidationService.call(user: user, course: course)
#   result[:eligible]    # => true or false
#   result[:requirements] # => [{type:, rule:, met:, waivable:, min_grade:}, ...]
class PrerequisiteValidationService < ApplicationService
  def initialize(user:, course:)
    @user = user
    @course = course
    super()
  end

  def call
    prerequisites = @course.course_prerequisites

    if prerequisites.empty?
      return { eligible: true, requirements: [] }
    end

    results = prerequisites.map { |prereq| validate_prereq(prereq) }
    all_met = results.all? { |r| r[:met] }

    { eligible: all_met, requirements: results }
  end

  private

  # Returns array of normalized course codes (e.g., "COMP1000") the user has completed.
  def completed_course_codes
    @completed_course_codes ||= @user.requirement_completions
                                     .where(in_progress: false)
                                     .pluck(:subject, :course_number)
                                     .map { |subject, number| "#{subject}#{number}" }
  end

  # Returns array of normalized course codes currently in progress.
  def in_progress_codes
    @in_progress_codes ||= @user.requirement_completions
                                .where(in_progress: true)
                                .pluck(:subject, :course_number)
                                .map { |subject, number| "#{subject}#{number}" }
  end

  def validate_prereq(prereq)
    ast = PrerequisiteParserService.call(rule_text: prereq.prerequisite_rule)
    met = evaluate_ast(ast, prereq.prerequisite_type)

    {
      type: prereq.prerequisite_type,
      rule: prereq.prerequisite_rule,
      met: met,
      waivable: prereq.waivable,
      min_grade: prereq.min_grade
    }
  end

  def evaluate_ast(node, prereq_type)
    case node[:type]
    when "course"
      eligible_codes = if prereq_type == "corequisite"
                         completed_course_codes + in_progress_codes
                       else
                         completed_course_codes
                       end
      eligible_codes.include?(node[:code])
    when "and"
      node[:operands].all? { |child| evaluate_ast(child, prereq_type) }
    when "or"
      node[:operands].any? { |child| evaluate_ast(child, prereq_type) }
    else
      # "special" nodes and unknown types cannot be auto-validated
      false
    end
  end

end
