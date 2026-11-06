# frozen_string_literal: true

module Dashboard
  # The My programs page (#867). It reads the hashes of
  # StudentProgramsSerializer and AcademicProfiles::DegreeProgress.
  module ProgramsHelper
    SEASON_ORDER = AcademicProfiles::TermCode::SEASON_SUFFIXES
    PROGRESS_BADGES = {
      "done"        => [ "Done", "m3-badge-primary" ],
      "in_progress" => [ "In progress", "m3-badge-tertiary" ],
      "open"        => [ "To do", "m3-badge-secondary" ]
    }.freeze
    KIND_GROUPS = {
      "associate"     => "Associate degrees",
      "bachelor"      => "Bachelor's degrees",
      "master"        => "Master's degrees",
      "minor"         => "Minors",
      "concentration" => "Concentrations",
      "certificate"   => "Certificates",
      "exploratory"   => "Exploratory programs"
    }.freeze

    def program_role_label(role) = role.to_s.humanize

    # The DegreeProgress result for one serialized program, or nil.
    def program_progress(progress, program)
      return nil if progress.nil? || program[:program].nil?

      progress[:programs].find do |entry|
        entry[:program] == program[:program] && entry[:catalog_year] == program[:catalog_year] &&
          entry[:status] == program[:status]
      end
    end

    # The plan rows of a program, by semester in plan order, each semester
    # with its real term: [[year, season, term label or nil], rows].
    def plan_semesters(program, progress_entry)
      start = AcademicProfiles::TermCode.parse(program[:start_term])
      rows = progress_entry[:requirements].select { |row| row[:year] && row[:season] }

      rows.group_by { |row| [ row[:year], row[:season] ] }
          .sort_by { |(year, season), _| [ year, SEASON_ORDER.fetch(season, 99) ] }
          .map do |(year, season), semester_rows|
            term = AcademicProfiles::TermCode.label(AcademicProfiles::ProgramTimeline.term_uid(start, year, season))
            [ [ year, season, term ], semester_rows ]
          end
    end

    def plan_semester_title(year, season) = "Year #{year}, #{season}"

    def progress_badge(status)
      label, css = PROGRESS_BADGES.fetch(status, [ status.to_s.humanize, "m3-badge-secondary" ])
      tag.span(label, class: "m3-badge #{css}")
    end

    # The text of one requirement row: its code, its options, or its label.
    def requirement_text(row)
      return row[:code] if row[:kind] == "course"
      return row[:options].join(" or ") if row[:kind] == "choice" && row[:options].present?
      return "#{row[:elective_list]}: #{requirement_minimum(row)}" if row[:kind] == "elective_list"

      row[:label] || row[:code] || row[:elective_list].to_s
    end

    # The open rows of a planned program: the courses it adds. A row that an
    # active program also requires is marked shared, because one course can count for both. For a
    # choice, one shared option is enough.
    def courses_added(progress, planned_entry)
      active_codes = progress[:programs].select { |entry| entry[:status] == "active" }
                                        .flat_map { |entry| entry[:requirements] }
                                        .flat_map { |row| [ row[:code], *row[:options] ] }
                                        .compact.to_set
      planned_entry[:requirements].reject { |row| row[:status] == "done" }.map do |row|
        codes = [ row[:code], *row[:options] ].compact
        { row: row, shared: codes.any? { |code| active_codes.include?(code) } }
      end
    end

    # Options for the "plan a program" select, grouped by kind.
    def catalog_program_options(requirement_sets)
      requirement_sets.group_by { |set| set.degree_program.kind }
                      .sort_by { |kind, _| DegreeProgram::KINDS.values.index(kind) || 99 }
                      .map { |kind, sets| [ KIND_GROUPS.fetch(kind, kind.humanize), sets.map { |set| [ set.name, set.degree_program.slug ] } ] }
    end

    private

    def requirement_minimum(row)
      return "pick #{row[:min_courses]}" if row[:min_courses]
      return "#{row[:min_credits]} credits" if row[:min_credits]

      "every course"
    end
  end
end
