# frozen_string_literal: true

module AcademicProfiles
  # A student's plan of study as a graph (#449, #448): one node for each row
  # of the plan, grouped by semester, with an edge from a course to each plan
  # course that lists it as a prerequisite. The status of each node comes from
  # AcademicProfiles::DegreeProgress, so it is done, in_progress, or open.
  #
  # Without a program argument, it shows the student's major with a plan of
  # study, before a minor.
  #
  # next_semester is the first semester after the last one with a done or
  # in-progress row that still has an open row WIT Calendar can check: the
  # courses the student registers for next, when they follow the plan. Open
  # rows of earlier semesters are listed in behind, so a course with AP or
  # transfer credit that WIT Calendar does not know does not hold the student
  # in Year 1. A free elective cannot be checked, so it never makes a
  # semester next.
  #
  # A focus course adds the courses that come before it (its prerequisites)
  # and the courses it unlocks, each with the student's status. The focus can
  # be any catalog course, also one outside the plan.
  #
  # GET /api/user/curriculum_graph and /dashboard/curriculum send it. Like
  # DegreeProgress, it is a help for planning, not a degree audit.
  class CurriculumGraph
    SEASON_NAMES = { "fall" => "Fall", "spring" => "Spring", "summer" => "Summer" }.freeze

    def initialize(user, program: nil, catalog_year: nil, plan: nil, focus: nil, today: Time.zone.today)
      @user = user
      @program = program.presence&.to_s
      @catalog_year = catalog_year.presence&.to_s
      @plan = plan.presence&.to_s
      @focus = focus.presence&.to_s
      @today = today
    end

    # Raises DegreeProgress::NoProgramError, or Catalog::FilterError for a bad
    # program, catalog year, or plan.
    def call
      @progress = DegreeProgress.new(@user, program: @program, catalog_year: @catalog_year, plan: @plan, today: @today)
      progress = @progress.call
      @statuses = course_statuses(progress[:courses])
      program = pick_program(progress[:programs])
      nodes = nodes_for(program)
      semesters = semesters_for(nodes)
      upcoming = semesters.find { |semester| semester[:next] }

      {
        program:       program[:program],
        name:          program[:name],
        catalog_year:  program[:catalog_year],
        plan:          program[:plan],
        plans:         program[:plans],
        programs:      own_programs,
        counts:        program[:counts],
        semesters:     semesters,
        next_semester: upcoming&.slice(:year, :season, :label),
        behind:        behind(semesters, upcoming),
        edges:         edges_for(nodes),
        focus:         focus_json,
        assumptions:   progress[:assumptions]
      }
    end

    # The student's own programs that link to an imported catalog year, so a
    # page can switch between them. Majors come first.
    def own_programs
      @own_programs ||= begin
        programs = @user.student_programs.active.includes(:degree_program, :catalog_year).order(:id).filter_map do |program|
          next if program.degree_program.nil? || !program.catalog_year&.imported?

          { program: program.degree_program.slug, name: program.degree_program.name,
            catalog_year: program.catalog_year.name, role: program.role }
        end
        programs.uniq { |program| program[:program] }
                .each_with_index.sort_by { |program, index| [ program[:role] == "major" ? 0 : 1, index ] }
                .map(&:first)
      end
    end

    private

    # The program argument, or the student's first major with a plan of
    # study. A minor has no plan, so it comes last.
    def pick_program(programs)
      return programs.first if @program

      order = own_programs.each_with_index.to_h { |program, index| [ program[:program], index ] }
      programs.each_with_index.min_by do |program, index|
        [ program[:plan] ? 0 : 1, order.fetch(program[:program], order.size), index ]
      end.first
    end

    # One node for each plan row. A program with no plan of study, such as a
    # minor, has no nodes.
    def nodes_for(program)
      return [] if program[:plan].nil?

      program[:requirements].each_with_index.map do |row, index|
        {
          id:            "n#{index + 1}",
          year:          row[:year],
          season:        row[:season],
          kind:          row[:kind],
          code:          row[:code],
          label:         row[:label],
          options:       row[:options],
          elective_list: row[:elective_list],
          status:        row[:status],
          checkable:     row[:checkable],
          course:        row[:course],
          term:          row[:term]
        }
      end
    end

    # The semesters in plan order, with the next one marked.
    def semesters_for(nodes)
      semesters = nodes.group_by { |node| [ node[:year], node[:season] ] }.map do |(year, season), group|
        { year: year, season: season, label: "Year #{year} #{SEASON_NAMES.fetch(season, season.to_s.titleize)}",
          next: false, nodes: group }
      end
      index = next_index(semesters)
      semesters[index][:next] = true if index
      semesters
    end

    # The first semester after the last one the student started that has an
    # open row to check. When no later semester has one, the first semester
    # with an open row to check.
    def next_index(semesters)
      started = semesters.rindex { |semester| semester[:nodes].any? { |node| node[:status] != "open" } } || -1
      openable = ->(semester) { semester[:nodes].any? { |node| open_to_check?(node) } }
      later = semesters.each_index.find { |index| index > started && openable.call(semesters[index]) }
      later || semesters.index(&openable)
    end

    def open_to_check?(node) = node[:status] == "open" && node[:checkable]

    # The open rows to check in the semesters before the next one.
    def behind(semesters, upcoming)
      return [] if upcoming.nil?

      semesters.take_while { |semester| !semester.equal?(upcoming) }.flat_map do |semester|
        semester[:nodes].select { |node| open_to_check?(node) }
                        .map { |node| node.slice(:id, :kind, :code, :label, :options).merge(semester: semester[:label]) }
      end
    end

    # An edge from each node of a prerequisite to each node of the course
    # that needs it. A node stands for its own code and the course that met
    # it. A choice that is still open stands for each of its options.
    def edges_for(nodes)
      nodes_for = Hash.new { |hash, code| hash[code] = [] }
      nodes.each do |node|
        codes = node[:course] ? [ node[:code], node[:course] ] : [ node[:code], *node[:options] ]
        codes.compact.uniq.each { |code| nodes_for[code] << node[:id] }
      end
      return [] if nodes_for.empty?

      courses = catalog_courses(nodes_for.keys)
      return [] if courses.empty?

      CoursePrerequisite.where(catalog_course_id: courses.keys, required_catalog_course_id: courses.keys)
                        .pluck(:required_catalog_course_id, :catalog_course_id)
                        .flat_map do |required_id, course_id|
        nodes_for.fetch(courses[required_id], []).product(nodes_for.fetch(courses[course_id], []))
                 .reject { |from, to| from == to }
                 .map { |from, to| { from: from, to: to } }
      end.uniq
    end

    # The catalog courses with these codes ("COMP 1000"), as id => code.
    def catalog_courses(codes)
      pairs = codes.filter_map do |code|
        subject, number = code.split
        [ subject, number.to_i ] if subject && number
      end
      return {} if pairs.empty?

      conditions = pairs.map { "(subject_code = ? AND course_number = ?)" }.join(" OR ")
      CatalogCourse.where(conditions, *pairs.flatten).pluck(:id, :subject_code, :course_number)
                   .to_h { |id, subject, number| [ id, "#{subject} #{number}" ] }
    end

    # The focus course with what comes before it and what it unlocks. Nil
    # without a focus. Raises Catalog::FilterError for an unknown code.
    def focus_json
      return nil if @focus.nil?

      course = Catalog::CourseQuery.new.find(@focus)
      raise Catalog::FilterError, "No course #{@focus} in WIT Calendar" if course.nil?

      {
        code:          course.code,
        title:         course.title,
        status:        status_of(course.code),
        prerequisites: Catalog::CourseSerializer.new(course).as_json[:prerequisites],
        before:        neighbors(course.prerequisite_courses),
        after:         neighbors(course.unlocks)
      }
    end

    def neighbors(scope)
      scope.distinct.order(:subject_code, :course_number).map do |course|
        { code: course.code, title: course.title, status: status_of(course.code) }
      end
    end

    # The best status of each course the student took, by code, also under
    # its old or new codes (CourseCodeAlias). A course not passed is open
    # again.
    def course_statuses(courses)
      courses.each_with_object({}) do |course, statuses|
        status = course[:status] == "not_passed" ? "open" : course[:status]
        subject, number = course[:code].split
        @progress.equivalent_keys([ subject, number.to_i ]).each do |key|
          code = key.join(" ")
          statuses[code] = status if statuses[code].nil? || rank(status) < rank(statuses[code])
        end
      end
    end

    def rank(status) = { "done" => 0, "in_progress" => 1 }.fetch(status, 2)

    def status_of(code) = @statuses.fetch(code, "open")
  end
end
