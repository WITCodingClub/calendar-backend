# frozen_string_literal: true

module AcademicProfiles
  # A student's plan of study as a graph (#449, #448): one node for each row
  # of the plan, grouped by semester, with an edge from a course to each plan
  # course that lists it as a prerequisite. The status of each node comes from
  # AcademicProfiles::DegreeProgress, so it is done, in_progress, or open.
  #
  # next_semester is the first semester with an open row that can be
  # checked: the courses the student registers for next, when they follow the
  # plan. A free elective cannot be checked, so it stays open and does not
  # hold the next semester back.
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
      progress = DegreeProgress.new(@user, program: @program, catalog_year: @catalog_year, plan: @plan, today: @today).call
      @statuses = course_statuses(progress[:courses])
      program = progress[:programs].first
      nodes = nodes_for(program)
      semesters = semesters_for(nodes)

      {
        program:       program[:program],
        name:          program[:name],
        catalog_year:  program[:catalog_year],
        plan:          program[:plan],
        plans:         program[:plans],
        programs:      own_programs,
        counts:        program[:counts],
        semesters:     semesters,
        next_semester: semesters.find { |semester| semester[:next] }&.slice(:year, :season, :label),
        edges:         edges_for(nodes),
        focus:         focus_json,
        assumptions:   progress[:assumptions]
      }
    end

    private

    # The student's own programs that link to an imported catalog year, so a
    # page can switch between them.
    def own_programs
      @user.student_programs.active.includes(:degree_program, :catalog_year).order(:id).filter_map do |program|
        next if program.degree_program.nil? || !program.catalog_year&.imported?

        { program: program.degree_program.slug, name: program.degree_program.name, catalog_year: program.catalog_year.name }
      end.uniq
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

    # The semesters in plan order. The first one with an open row is next.
    def semesters_for(nodes)
      next_found = false
      nodes.group_by { |node| [ node[:year], node[:season] ] }.map do |(year, season), group|
        upcoming = !next_found && group.any? { |node| node[:status] == "open" && node[:checkable] }
        next_found ||= upcoming
        { year: year, season: season, label: "Year #{year} #{SEASON_NAMES.fetch(season, season.to_s.titleize)}",
          next: upcoming, nodes: group }
      end
    end

    # An edge from the node of a prerequisite to the node of the course that
    # needs it. A node stands for its own code, the options of a choice, and
    # the course that met it.
    def edges_for(nodes)
      node_for = {}
      nodes.each do |node|
        [ node[:code], *node[:options], node[:course] ].compact.each { |code| node_for[code] ||= node[:id] }
      end
      return [] if node_for.empty?

      courses = catalog_courses(node_for.keys)
      return [] if courses.empty?

      CoursePrerequisite.where(catalog_course_id: courses.keys, required_catalog_course_id: courses.keys)
                        .pluck(:required_catalog_course_id, :catalog_course_id)
                        .filter_map do |required_id, course_id|
        from = node_for[courses[required_id]]
        to = node_for[courses[course_id]]
        { from: from, to: to } if from && to && from != to
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

    # The best status of each course the student took, by code. A course not
    # passed is open again.
    def course_statuses(courses)
      courses.each_with_object({}) do |course, statuses|
        status = course[:status] == "not_passed" ? "open" : course[:status]
        current = statuses[course[:code]]
        statuses[course[:code]] = status if current.nil? || rank(status) < rank(current)
      end
    end

    def rank(status) = { "done" => 0, "in_progress" => 1 }.fetch(status, 2)

    def status_of(code) = @statuses.fetch(code, "open")
  end
end
