# frozen_string_literal: true

module DegreeRequirements
  # Imports the plans of study of one PDF catalog year (2013-2014 to
  # 2018-2019) from the `pdftotext -layout` text of its PDF.
  #
  # Each set it writes has needs_review, until a person checks it in the
  # review queue (/admin/requirement_set_reviews). The checks that failed in
  # the parse go into review_notes. A plan that the parser left out, or whose
  # heading names no known program, is not written; the result counts them.
  #
  # A set that did not change since the last import keeps its review. A
  # changed set needs a review again. A set from the HTML catalog or the
  # Wayback Machine is never written over.
  class PdfImporter
    Result = Data.define(:status, :imported, :unchanged, :kept, :unmatched, :left_out)

    # Part of the digest. Raise it when a parser change should write every
    # set again.
    VERSION = 1

    def initialize(catalog_year, text:, matcher: PdfProgramMatcher.new)
      @catalog_year = catalog_year
      @text = text
      @matcher = matcher
      @stats = Hash.new(0)
    end

    def call
      parser = PdfCatalog.parser_for(@catalog_year.start_year)
      raise Error, "#{@catalog_year.name} has no PDF parser" if parser.nil?

      parsed = parser.call(@text)
      # Empty or broken text would mark every stored set as unlisted.
      raise Error, "#{@catalog_year.name}: the PDF text has no plan of study" if parsed.plans.empty?

      parsed.rejections.each { |rejection| log("left out the plan at line #{rejection.line} (#{rejection.heading}): #{rejection.reason}") }
      @stats[:left_out] = parsed.rejections.size
      # A program with a plan that the parser left out may keep only a part
      # of its plans, such as the first page of a plan that goes on.
      rejected = parsed.rejections.filter_map { |rejection| @matcher.call(rejection.heading)&.program&.id }.to_set

      by_program(parsed.plans).each do |matches, plans|
        program = matches.first.program
        if rejected.include?(program.id)
          @stats[:left_out] += plans.size
          log("#{program.slug}: left out, another of its plans did not parse")
          next
        end

        import_program(program, plans)
      end

      ProgramPlanItem.link_catalog_courses
      AcademicProfiles::ProgramMatcher.relink_active
      unless @catalog_year.requirement_sets.where.not(source: "pdf").exists?
        @catalog_year.update!(source: "pdf", base_url: PdfCatalog.url_for(@catalog_year.start_year))
      end
      @catalog_year.update!(status: "imported", imported_at: Time.current)

      Result.new(status: :imported, **Result.members.drop(1).index_with { |key| @stats[key] }).tap do |result|
        log("#{result.imported} imported, #{result.unchanged} unchanged, #{result.kept} kept, " \
            "#{result.unmatched} plans with no program, #{result.left_out} plans left out")
      end
    end

    private

    # [[match, plan], ...] for each program. A plan whose heading has no
    # program is counted and left out.
    def by_program(plans)
      matched = plans.filter_map do |plan|
        match = @matcher.call(plan.heading)
        if match.nil?
          @stats[:unmatched] += 1
          log("no program for #{plan.heading} (line #{plan.line})")
        end
        match && [ match, plan ]
      end
      matched.group_by { |match, _| match.program.id }.values.map { |pairs| [ pairs.map(&:first), pairs.map(&:last) ] }
    end

    def import_program(program, plans)
      named = plan_list(program, plans)
      return if named.nil?

      set = RequirementSet.find_or_initialize_by(degree_program: program, catalog_year: @catalog_year)
      if set.persisted? && !set.source_pdf?
        @stats[:kept] += 1
        return
      end

      now = Time.current
      digest = Digest::SHA256.hexdigest("#{VERSION}:#{named.map { |name, plan| [ name, plan.heading, plan.items.map(&:to_h), plan.warnings ] }.to_json}")
      if set.persisted? && set.source_digest == digest
        set.update_columns(last_seen_at: now)
        @stats[:unchanged] += 1
        return
      end

      RequirementSet.transaction do
        set.update!(name: display_name(named.first.last.heading), source: "pdf", needs_review: true, reviewed_at: nil,
                    review_notes: notes(named), total_credits: named.first.last.total_credits, path: nil,
                    source_digest: digest, fetched_at: now, last_seen_at: now)
        write_plans(set, named)
      end
      @stats[:imported] += 1
    end

    # [[plan name, plan], ...]. The same plan printed twice is kept once.
    # Two different plans with the same name leave the program out, because
    # the import cannot tell which one is right.
    def plan_list(program, plans)
      pairs = plans.uniq(&:items).map { |plan| [ @matcher.call(plan.heading).plan_name, plan ] }
      return pairs if pairs.map(&:first).uniq.size == pairs.size

      @stats[:left_out] += pairs.size
      log("#{program.slug}: two different plans named #{pairs.map(&:first).tally.select { |_, n| n > 1 }.keys.join(', ')}")
      nil
    end

    def notes(named)
      lines = named.flat_map do |name, plan|
        plan.warnings.map { |warning| named.size > 1 ? "#{name}: #{warning}" : warning }
      end
      lines.join("\n").presence
    end

    # "COMPUTER SCIENCE (BCOS)" becomes "Computer Science (BCOS)".
    def display_name(heading)
      return heading if heading.match?(/[a-z]/)

      heading.split(/(\([^)]*\))/).map do |part|
        part.start_with?("(") ? part : part.downcase.gsub(/\b[a-z]/) { |letter| letter.upcase }.gsub(/\b(And|Of|In|For)\b/, &:downcase)
      end.join
    end

    def write_plans(set, named)
      set.elective_groups.delete_all
      plans = named.each_with_index.map do |(name, data), position|
        plan = set.program_plans.find_or_initialize_by(position: position)
        plan.update!(name: name, years: data.years, accelerated: false, total_credits: data.total_credits)
        plan
      end
      set.program_plans.where(position: named.size..).delete_all
      ProgramPlanItem.where(program_plan_id: plans.map(&:id)).delete_all

      rows = named.each_with_index.flat_map do |(_, data), index|
        data.items.each_with_index.map do |item, position|
          { program_plan_id: plans[index].id, position: position, year_index: item.year_index, season: item.season,
            kind: item.kind, subject_code: item.subject_code, course_number: item.course_number,
            label: item.label.presence, min_credits: item.min_credits, max_credits: item.max_credits,
            options: item.options }
        end
      end
      ProgramPlanItem.insert_all!(rows) if rows.any?
    end

    def log(message)
      Rails.logger.info("[DegreeRequirements::PdfImporter] #{@catalog_year.name}: #{message}")
    end
  end
end
