# frozen_string_literal: true

module Catalog
  # One degree program in one catalog year (RequirementSet) as the public
  # catalog API and the MCP tools return it. The summary is for lists. The
  # full form adds the plans of study, semester by semester, and the
  # elective lists that the plans name.
  #
  # Each course gets its title as that catalog year printed it
  # (CatalogYearCourse), or Banner's title when the year has no row.
  class ProgramSerializer
    def initialize(requirement_set, summary: false)
      @set = requirement_set
      @summary = summary
    end

    def self.summary(requirement_set) = new(requirement_set, summary: true).as_json

    def as_json(*)
      program = @set.degree_program
      json = {
        slug:            program.slug,
        name:            @set.name,
        kind:            program.kind,
        level:           program.level,
        school:          @set.school_name,
        department:      @set.department_name,
        catalog_year:    @set.catalog_year.name,
        total_credits:   @set.total_credits,
        parent_program:  program.parent_program&.slug,
        catalog_url:     @set.catalog_url,
        listed:          @set.listed?
      }
      return json if @summary

      json.merge(
        description:    @set.description,
        needs_review:   @set.needs_review,
        source:         @set.source,
        plans:          @set.program_plans.map { |plan| plan_json(plan) },
        elective_lists: @set.elective_groups.map { |group| group_json(group) }
      )
    end

    private

    def plan_json(plan)
      {
        name:          plan.name,
        years:         plan.years,
        accelerated:   plan.accelerated,
        total_credits: plan.total_credits,
        terms:         plan.items.group_by { |item| [ item.year_index, item.season ] }.map do |(year, season), items|
          { year: year, season: season, items: items.map { |item| item_json(item) } }
        end
      }
    end

    def item_json(item)
      {
        kind:          item.kind,
        code:          item.code,
        title:         item.course? ? title_for(item.subject_code, item.course_number) || item.label : item.label,
        min_credits:   item.min_credits,
        max_credits:   item.max_credits,
        footnote:      item.footnote,
        options:       item.options.map { |option| course_json(option["subject_code"], option["course_number"]) },
        elective_list: item.elective_group&.name
      }
    end

    def group_json(group)
      {
        name:        group.name,
        heading:     group.heading,
        plan:        group.program_plan&.name,
        min_courses: group.min_courses,
        min_credits: group.min_credits,
        notes:       group.notes,
        courses:     group.courses.map do |course|
          course_json(course.subject_code, course.course_number).merge(requires_approval: course.requires_approval)
        end
      }
    end

    def course_json(subject_code, course_number)
      { code: "#{subject_code} #{course_number}", title: title_for(subject_code, course_number) }
    end

    def title_for(subject_code, course_number)
      titles[[ subject_code, course_number.to_i ]]
    end

    # One query for the titles of every course the program names.
    def titles
      @titles ||= begin
        codes = (@set.program_plans.flat_map(&:items).flat_map { |item| item_codes(item) } +
                 @set.elective_groups.flat_map(&:courses).map { |course| [ course.subject_code, course.course_number ] }).uniq
        if codes.empty?
          {}
        else
          # The year's title wins. A year row with no title keeps Banner's.
          banner = CatalogCourse.where(code_condition(codes), *codes.flatten).where.not(title: nil)
                                .pluck(:subject_code, :course_number, :title)
          year = @set.catalog_year.catalog_year_courses.where(code_condition(codes), *codes.flatten).where.not(title: nil)
                     .pluck(:subject_code, :course_number, :title)
          (banner + year).to_h { |subject, number, title| [ [ subject, number ], title ] }
        end
      end
    end

    def item_codes(item)
      codes = item.options.map { |option| [ option["subject_code"], option["course_number"].to_i ] }
      item.course? ? codes << [ item.subject_code, item.course_number ] : codes
    end

    def code_condition(codes)
      codes.map { "(subject_code = ? AND course_number = ?)" }.join(" OR ")
    end
  end
end
