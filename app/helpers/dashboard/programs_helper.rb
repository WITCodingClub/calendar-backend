# frozen_string_literal: true

module Dashboard
  # The My programs page (#867). It reads the hashes of
  # StudentProgramsSerializer and AcademicProfiles::DegreeProgress.
  module ProgramsHelper
    PROGRESS_BADGES = {
      "done"        => [ "Done", "m3-badge-primary" ],
      "in_progress" => [ "In progress", "m3-badge-tertiary" ],
      "registered"  => [ "Registered", "m3-badge-tertiary" ],
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

    def program_progress(progress, program)
      progress && AcademicProfiles::DegreeProgress.entry_for(progress, program)
    end

    # The plan rows of a program, by semester in plan order, each semester
    # with its planned term (PlanTerms): [[year, season, term label or nil], rows].
    def plan_semesters(progress_entry)
      AcademicProfiles::ProgramTimeline.semesters(nil, progress_entry[:requirements]).map do |semester|
        [ [ semester.year, semester.season, semester.rows.first[:planned_term] ], semester.rows ]
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

    # The text of one row of AcademicProfiles::NextTermCourses: its code,
    # "one of" its options, or its label with its elective list.
    def next_term_row_text(row)
      return row[:code] if row[:kind] == "course"
      return "One of: #{row[:courses].pluck(:code).join(', ')}" if row[:kind] == "choice"

      [ row[:label], (row[:elective_list] if row[:elective_list] && row[:elective_list] != row[:label]) ].compact.join(": ")
    end

    def next_term_offered_badge(offered)
      return nil if offered.nil?

      offered ? tag.span("Offered", class: "m3-badge m3-badge-primary") : tag.span("No section", class: "m3-badge m3-badge-secondary")
    end

    def next_term_prerequisite_badge(course)
      case course[:prerequisites]
      when "met" then tag.span("Prerequisites met", class: "m3-badge m3-badge-primary")
      when "not_met" then tag.span("Needs #{course[:missing].join(', ')}", class: "m3-badge m3-badge-tertiary")
      when "unknown" then tag.span("Check prerequisites", class: "m3-badge m3-badge-secondary")
      end
    end

    # The rows of a planned program that are not done: the courses it adds.
    # A row that an active program also has is marked shared, because one
    # course can count for both, with the rows that the overlap of
    # GET /api/user/degree_progress compares (AcademicProfiles::ActiveRows).
    def courses_added(progress, planned_entry)
      @active_rows ||= {}.compare_by_identity
      rows = @active_rows[progress] ||= AcademicProfiles::ActiveRows.new(
        progress[:programs].select { |entry| entry[:status] == "active" }, AcademicProfiles::CourseKeys.current
      )
      rows.added_rows(planned_entry)
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
