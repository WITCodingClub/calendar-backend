# frozen_string_literal: true

module DegreeRequirements
  # Imports the programs of one catalog year: the program index, then each
  # program page. A page that did not change since the last import (the same
  # digest) is skipped. A fetch error stops the import and leaves the stored
  # data as it was; the job retries.
  #
  # Plans keep their ids across imports, so later tables can point to them.
  # Plan rows and elective lists are written again each time a page changes.
  class Importer
    Result = Data.define(:status, :programs, :updated, :unchanged, :skipped)

    # Below this many stored programs, a short index is not a warning sign.
    SHRINK_FLOOR = 10

    # force: true skips the check for a short index, after a person confirms
    # that the catalog really lists fewer programs.
    def initialize(catalog_year, client: CatalogSiteClient.new, force: false)
      @catalog_year = catalog_year
      @client = client
      @force = force
      @stats = Hash.new(0)
    end

    def call
      source = CatalogSource.locate(start_year, client: @client)
      if source.nil?
        # A year with stored data keeps its status: the site may be down for
        # a moment, and the data is still good.
        @catalog_year.update!(status: "missing") unless @catalog_year.requirement_sets.exists?
        log("no source has this catalog year")
        return result(:missing, 0)
      end

      index = ProgramIndexParser.new(source.index_html, home_path: source.home_path)
      entries = index.entries.uniq(&:slug)
      check_shrink!(entries.size) unless @force
      log("left out #{index.unclassified.size} links with no program kind: #{index.unclassified.join(', ')}") if index.unclassified.any?

      @catalog_year.update!(source: source.catalog_year_source, base_url: source.base_url)
      programs = entries.filter_map { |entry| (program = import_entry(source, entry)) && [ entry, program ] }
      link_parents(programs)
      ProgramPlanItem.link_catalog_courses
      ElectiveGroupCourse.link_catalog_courses
      # Student programs saved before this import get their link now.
      AcademicProfiles::ProgramMatcher.relink_active

      @catalog_year.update!(status: "imported", imported_at: Time.current)
      result(:imported, programs.size).tap do |done|
        log("#{done.programs} programs: #{done.updated} updated, #{done.unchanged} unchanged, #{done.skipped} skipped")
      end
    end

    private

    def start_year = @catalog_year.start_year

    def result(status, programs)
      Result.new(status: status, programs: programs, updated: @stats[:updated], unchanged: @stats[:unchanged],
                 skipped: @stats[:skipped])
    end

    # Compares with the programs the last import saw. Sets of programs that
    # left the catalog earlier stay stored, so they do not count.
    def check_shrink!(count)
      sets = @catalog_year.requirement_sets
      sets = sets.where(last_seen_at: (@catalog_year.imported_at - 1.day)..) if @catalog_year.imported_at
      previous = sets.count
      return if previous < SHRINK_FLOOR || count >= previous / 2

      raise ImportShrankError, "#{@catalog_year.name}: the index lists #{count} programs, the last import had #{previous}. " \
                               "If that is right, import again with force"
    end

    # The DegreeProgram for one index entry, or nil when its page is missing,
    # is from another catalog year, or does not parse.
    def import_entry(source, entry)
      html = @client.get(source.url_for(entry.path))
      page = html && ProgramPageParser.new(html).call
      if page.nil? || page.start_year != start_year
        @stats[:skipped] += 1
        log("skipped #{entry.path}: #{page ? "the page is from #{page.start_year}" : 'not found'}")
        return nil
      end

      import_program(source, entry, page)
    rescue FetchError
      raise
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { catalog_year_id: @catalog_year.id, path: entry.path })
      @stats[:skipped] += 1
      nil
    end

    def import_program(source, entry, page)
      program = DegreeProgram.find_or_initialize_by(slug: entry.slug)
      # The newest catalog year names the program.
      if program.new_record? || program.catalog_years.maximum(:start_year).to_i <= start_year
        program.assign_attributes(name: entry.name, kind: entry.kind, level: entry.level)
        program.save! if program.changed?
      end

      set = RequirementSet.find_or_initialize_by(degree_program: program, catalog_year: @catalog_year)
      now = Time.current
      if set.persisted? && set.source_digest == page.digest
        set.update_columns(last_seen_at: now)
        @stats[:unchanged] += 1
        return program
      end

      RequirementSet.transaction do
        set.update!(name: entry.name, path: entry.path, school_name: page.school_name,
                    department_name: page.department_name, description: page.description,
                    total_credits: page.total_credits, source: source.catalog_year_source, needs_review: false,
                    source_digest: page.digest, fetched_at: now, last_seen_at: now)
        write_plans(set, page)
      end
      @stats[:updated] += 1
      program
    end

    def write_plans(set, page)
      set.elective_groups.delete_all
      plans = page.plans.each_with_index.map do |data, position|
        plan = set.program_plans.find_or_initialize_by(position: position)
        plan.update!(name: data.name, years: data.years, accelerated: data.accelerated, total_credits: data.total_credits)
        plan
      end
      set.program_plans.where(position: page.plans.size..).delete_all
      ProgramPlanItem.where(program_plan_id: plans.map(&:id)).delete_all

      groups = page.groups.each_with_index.map do |data, position|
        ElectiveGroup.create!(requirement_set: set, program_plan: data.plan_index && plans[data.plan_index],
                              name: data.name, heading: data.heading, min_courses: data.min_courses,
                              min_credits: data.min_credits, notes: data.notes, position: position)
      end

      insert_group_courses(page.groups, groups)
      insert_plan_items(page.plans, plans, groups)
    end

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

    # "Building Sciences, B.S. - Construction Management Concentration" belongs
    # to the "Building Sciences, B.S." of the same catalog year.
    # The newest catalog year sets the parent, the same as the name.
    def link_parents(programs)
      by_name = programs.to_h { |entry, program| [ name_key(entry.name), program ] }
      programs.each do |entry, program|
        parent = entry.parent_name && by_name[name_key(entry.parent_name)]
        next if parent.nil? || parent == program || program.parent_program_id == parent.id
        next if program.catalog_years.maximum(:start_year).to_i > start_year

        program.parent_program = parent
        log("#{program.slug}: #{program.errors.full_messages.to_sentence}") unless program.save
      end
    end

    def name_key(name)
      name.downcase.gsub(/bachelor of science(?: degree)?|\bb\.?\s?s\b\.?/, "bs").gsub(/[^a-z0-9]/, "")
    end

    def log(message)
      Rails.logger.info("[DegreeRequirements::Importer] #{@catalog_year.name}: #{message}")
    end
  end
end
