# frozen_string_literal: true

# Banner added the "Study Away Domestic (SAD)" schedule type. The check
# constraint lists every allowed code, so it must allow the new code too.
class AddStudyAwayDomesticScheduleType < ActiveRecord::Migration[8.1]
  OLD_CODES = %w[EXT HYB IND LAB LEC ONL ONB OLB OLC RLB RLC SAB].freeze
  NEW_CODES = (OLD_CODES + %w[SAD]).freeze

  def up
    replace_schedule_type_constraint(NEW_CODES)
  end

  def down
    replace_schedule_type_constraint(OLD_CODES)
  end

  private

  def replace_schedule_type_constraint(codes)
    remove_check_constraint :courses, name: "courses_schedule_type_valid"
    add_check_constraint :courses,
                         "schedule_type IN (#{codes.map { |code| connection.quote(code) }.join(', ')})",
                         name: "courses_schedule_type_valid"
  end
end
