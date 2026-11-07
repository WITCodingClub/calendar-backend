# frozen_string_literal: true

module DegreeRequirements
  # Writes the plans and elective lists of one requirement set, from a
  # program page (Importer) or a PDF (PdfCatalog::Importer). Plans keep
  # their ids, so later tables can point to them. Plan rows and elective
  # lists are written again each time.
  class PlanWriter
    def self.call(set, plans:, groups:) = new(set, plans, groups).call

    def initialize(set, plans, groups)
      @set = set
      @plans = plans
      @groups = groups
    end

    def call
      @set.elective_groups.delete_all
      plans = @plans.each_with_index.map do |data, position|
        plan = @set.program_plans.find_or_initialize_by(position: position)
        plan.update!(name: data.name, years: data.years, accelerated: data.accelerated, total_credits: data.total_credits)
        plan
      end
      @set.program_plans.where(position: @plans.size..).delete_all
      ProgramPlanItem.where(program_plan_id: plans.map(&:id)).delete_all

      groups = @groups.each_with_index.map do |data, position|
        ElectiveGroup.create!(requirement_set: @set, program_plan: data.plan_index && plans[data.plan_index],
                              name: data.name, heading: data.heading, min_courses: data.min_courses,
                              min_credits: data.min_credits, notes: data.notes, position: position)
      end

      insert_group_courses(@groups, groups)
      insert_plan_items(@plans, plans, groups)
    end

    private

    def insert_group_courses(data, groups)
      rows = data.each_with_index.flat_map do |group, index|
        group.courses.each_with_index.map do |course, position|
          { elective_group_id: groups[index].id, subject_code: course.subject_code, course_number: course.course_number,
            requires_approval: course.requires_approval, position: position }
        end
      end
      ElectiveGroupCourse.insert_all!(rows) if rows.any?
    end

    def insert_plan_items(data, plans, groups)
      rows = data.each_with_index.flat_map do |plan, index|
        plan.items.each_with_index.map do |item, position|
          { program_plan_id: plans[index].id, position: position, year_index: item.year_index, season: item.season,
            kind: item.kind, subject_code: item.subject_code, course_number: item.course_number,
            label: item.label.presence, min_credits: item.min_credits, max_credits: item.max_credits,
            footnote: item.footnote, options: item.options,
            elective_group_id: item.group_index && groups[item.group_index].id }
        end
      end
      ProgramPlanItem.insert_all!(rows) if rows.any?
    end
  end
end
