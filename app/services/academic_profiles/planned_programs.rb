# frozen_string_literal: true

module AcademicProfiles
  # Adds and removes a student's planned programs (#868): programs from the
  # degree catalog that the student thinks about taking, such as a minor.
  # POST and DELETE /api/user/planned_programs and /api/user/planned_pathways
  # and the MCP tool update_my_planned_programs use it.
  #
  # A planned pathway (a ProgramPathway) is a planned row for each of its
  # programs that the student does not have yet, each linked to the pathway.
  # Removing the pathway removes those rows only. A Double Leopard pathway
  # names only the master's programs: it follows the student's own
  # bachelor's, so the student must have one.
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

      row = row_for(set, year)
      check!(row)
      row
    end

    # The pathway and the unsaved planned rows for its steps that the user
    # does not have yet (as an active or planned program). Each row links
    # to the pathway. pathway is a slug from the pathways list. A blank
    # catalog_year is the newest one. Raises InvalidProfileError.
    def build_pathway(pathway:, catalog_year: nil)
      raise InvalidProfileError, "pathway is required" unless pathway.is_a?(String) && pathway.present?
      raise InvalidProfileError, "catalog_year must be a string" unless catalog_year.nil? || catalog_year.is_a?(String)

      record = ProgramPathway.active.includes(steps: :degree_program).find_by(slug: pathway.strip.downcase)
      raise InvalidProfileError.new(unknown_pathway_message(pathway), code: "unknown_pathway") if record.nil?

      check_bachelors!(record)

      year = find_catalog_year(Catalog::ProgramQuery.new, catalog_year)
      steps = record.steps.reject { |step| held_program_ids.include?(step.degree_program_id) }
      sets = year.requirement_sets.includes(:degree_program).where(degree_program_id: steps.map(&:degree_program_id))
                 .index_by(&:degree_program_id)
      rows = steps.map do |step|
        set = sets[step.degree_program_id]
        raise InvalidProfileError.new("No program #{step.degree_program.slug} in the #{year.name} catalog", code: "unknown_program") if set.nil?

        row_for(set, year).tap { |row| row.program_pathway = record }
      end
      check_pathway!(record, rows)
      [ record, rows ]
    end

    # Saves the rows from build_pathway, all or none. The checks run again
    # under a lock on the user. Raises InvalidProfileError.
    def save_pathway!(pathway, rows)
      user.with_lock do
        @held_program_ids = nil
        held = rows.find { |row| held_program_ids.include?(row.degree_program_id) }
        raise InvalidProfileError.new("#{held.name} is already in your programs", code: "duplicate_program") if held
        check_pathway!(pathway, rows)
        rows.each(&:save!)
      end
      rows
    end

    # A pathway the user planned, by its slug, and its planned rows.
    # nil when the user has no planned row for that pathway.
    def find_pathway(key)
      rows = user.student_programs.planned.joins(:program_pathway)
                 .where(program_pathways: { slug: key.to_s.strip.downcase }).includes(:program_pathway).to_a
      rows.empty? ? nil : [ rows.first.program_pathway, rows ]
    end

    # Saves a row from build. The checks run again under a lock on the user,
    # so two adds at the same time cannot save the same program twice or
    # pass MAX_PLANNED. Raises InvalidProfileError.
    def save!(row)
      user.with_lock do
        check!(row)
        row.save!
      end
      row
    end

    # A planned row of the user by its public id, or by the slug of its
    # program. nil when the user has no such planned row.
    def find(key)
      key = key.to_s.strip
      return nil if key.empty?

      row = StudentProgram.find_by_public_id(key)
      return row if row&.user_id == user.id && row.planned?

      user.student_programs.planned.joins(:degree_program).find_by(degree_programs: { slug: DegreeProgram.current_slug(key.downcase) })
    end

    private

    # StudentProgram.new, not user.student_programs.build: an unsaved row in
    # the association would show in the user's programs when the student
    # declines the change.
    def row_for(set, year)
      degree_program = set.degree_program
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

    def check!(row)
      check_program!(row)
      check_limit!(1)
    end

    def check_program!(row)
      return unless user.student_programs.where(status: %w[active planned], degree_program_id: row.degree_program_id).exists?

      raise InvalidProfileError.new("#{row.name} is already in your programs", code: "duplicate_program")
    end

    def check_pathway!(pathway, rows)
      if user.student_programs.planned.exists?(program_pathway_id: pathway.id)
        raise InvalidProfileError.new("#{pathway.name} is already in your planned pathways", code: "duplicate_pathway")
      end
      if rows.empty?
        raise InvalidProfileError.new("Every program of #{pathway.name} is already in your programs", code: "duplicate_pathway")
      end

      check_limit!(rows.size)
    end

    # A Double Leopard master's follows a bachelor's. A LeopardWeb row with no
    # catalog program counts when its degree is a bachelor's.
    def check_bachelors!(pathway)
      return unless pathway.double_leopard?

      rows = user.student_programs.where(status: %w[active planned]).left_joins(:degree_program)
      bachelors = rows.where(degree_programs: { kind: "bachelor" })
                      .or(rows.where(degree_program_id: nil).where("student_programs.degree ILIKE ?", "%bachelor%"))
      return if bachelors.exists?

      raise InvalidProfileError.new("#{pathway.name} follows a bachelor's program. Add your bachelor's program first",
                                    code: "no_bachelors_program")
    end

    def check_limit!(added)
      return if user.student_programs.planned.count + added <= MAX_PLANNED

      raise InvalidProfileError.new("You can plan at most #{MAX_PLANNED} programs", code: "too_many_programs")
    end

    def unknown_pathway_message(key)
      slugs = ProgramPathway.active.order(:slug).pluck(:slug)
      return "No pathway #{key}. WIT Calendar has no program pathways yet" if slugs.empty?

      "No pathway #{key}. Pathways: #{slugs.join(', ')}"
    end

    # The DegreeProgram ids of the user's active and planned rows.
    def held_program_ids
      @held_program_ids ||= user.student_programs.where(status: %w[active planned]).where.not(degree_program_id: nil)
                                .pluck(:degree_program_id).to_set
    end

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
