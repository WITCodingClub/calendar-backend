# frozen_string_literal: true

module AcademicProfiles
  # Adds and removes a student's planned programs (#868): programs from the
  # degree catalog that the student thinks about taking, such as a minor.
  # POST and DELETE /api/user/planned_programs and the MCP tool
  # update_my_planned_programs use it.
  #
  # It changes only rows with status planned. LeopardWeb rows (active and
  # ended) never change here.
  class PlannedPrograms
    MAX_PLANNED = 10

    # The role of a planned row, from the kind of its DegreeProgram. Every
    # other kind (bachelor, master, associate, exploratory) is a major.
    ROLES_BY_KIND = { "minor" => "minor", "concentration" => "concentration", "certificate" => "certificate" }.freeze

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # An unsaved planned row for a program in the degree catalog. program is
    # a slug or the exact name, as degree_requirements takes it. A blank
    # catalog_year is the newest one. Raises InvalidProfileError.
    def build(program:, catalog_year: nil)
      raise InvalidProfileError, "program is required" unless program.is_a?(String) && program.present?
      raise InvalidProfileError, "catalog_year must be a string" unless catalog_year.nil? || catalog_year.is_a?(String)

      query = Catalog::ProgramQuery.new
      year = find_catalog_year(query, catalog_year)
      set = query.find(program.to_s, catalog_year: year)
      raise InvalidProfileError.new("No program #{program} in the #{year.name} catalog", code: "unknown_program") if set.nil?

      degree_program = set.degree_program
      if user.student_programs.where(status: %w[active planned], degree_program: degree_program).exists?
        raise InvalidProfileError.new("#{set.name} is already in your programs", code: "duplicate_program")
      end
      if user.student_programs.planned.count >= MAX_PLANNED
        raise InvalidProfileError.new("You can plan at most #{MAX_PLANNED} programs", code: "too_many_programs")
      end

      # StudentProgram.new, not user.student_programs.build: an unsaved row
      # in the association would show in the user's programs when the student
      # declines the change.
      StudentProgram.new(
        user:           user,
        status:         :planned,
        source:         :student,
        role:           ROLES_BY_KIND.fetch(degree_program.kind, "major"),
        name:           set.name,
        college:        set.school_name,
        department:     set.department_name,
        degree_program: degree_program,
        catalog_year:   year
      )
    end

    # A planned row of the user by its public id, or by the slug of its
    # program. nil when the user has no such planned row.
    def find(key)
      key = key.to_s.strip
      return nil if key.empty?

      row = StudentProgram.find_by_public_id(key)
      return row if row&.user_id == user.id && row.planned?

      user.student_programs.planned.joins(:degree_program).find_by(degree_programs: { slug: key.downcase })
    end

    private

    def find_catalog_year(query, value)
      year = query.catalog_year(value)
      return year if year

      raise InvalidProfileError.new("WIT Calendar has no degree program data yet", code: "unknown_catalog_year") if value.blank?

      raise InvalidProfileError.new("No #{value} catalog. WIT Calendar has these catalog years: " \
                                    "#{query.catalog_years.map(&:name).join(', ')}", code: "unknown_catalog_year")
    rescue Catalog::FilterError => e
      raise InvalidProfileError.new(e.message, code: "invalid_catalog_year")
    end
  end
end
