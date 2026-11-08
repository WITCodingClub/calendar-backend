# frozen_string_literal: true

module DegreeRequirements
  module PdfCatalog
    # Imports the plans of study of one catalog year from its PDF (#865).
    #
    # - 2013-2014 to 2018-2019 have only a PDF. The import writes every plan
    #   it can match to a DegreeProgram, and marks the year imported.
    # - 2025-2026 is read from the Wayback Machine first. The PDF fills in
    #   only the programs that have no set for the year yet, and the year
    #   keeps its source and status.
    #
    # Every set it writes has needs_review, until a person checks it against
    # the PDF on the admin review page. A set with the same PDF digest and
    # parser version is not written again, so a check is kept. A new PDF or
    # parser version that gives the same plans also keeps the check. A set
    # from the HTML catalog is never replaced.
    class Importer
      Result = Data.define(:status, :programs, :updated, :unchanged, :unmatched)

      # Part of the digest. Raise it when a parser change should read every
      # PDF again. A set whose plans then change is written again and needs
      # a new review. A set whose plans are the same is not written, so a
      # change to PlanWriter or SharedElectives needs its own rake task.
      VERSION = 3

      def initialize(catalog_year, client: CatalogSiteClient.new, matcher: nil)
        @catalog_year = catalog_year
        @client = client
        @matcher = matcher
        @stats = Hash.new(0)
      end

      def call
        url = PdfCatalog.url_for(start_year)
        raise ArgumentError, "#{@catalog_year.name} has no catalog PDF" if url.nil?

        pdf = @client.get(url, binary: true)
        if pdf.nil?
          @catalog_year.update!(status: "missing") if pdf_only? && !@catalog_year.requirement_sets.exists?
          log("the PDF is not on the catalog site: #{url}")
          return result(:missing, 0, [])
        end

        digest = Digest::SHA256.hexdigest("#{VERSION}:#{pdf}")
        programs = parse(Text.extract(pdf, columns: two_columns? ? 2 : 1))
        matched, unmatched = match(programs)
        log("no program for: #{unmatched.join('; ')}") if unmatched.any?

        if matched.empty? && pdf_only? && !@catalog_year.requirement_sets.exists?
          # Every plan failed to parse or to match: a parser bug, not an empty year.
          @catalog_year.update!(status: "failed")
          Rails.error.report(Error.new("#{@catalog_year.name}: the PDF gave no plan with a program"), handled: true,
                                                                                                    context: { catalog_year_id: @catalog_year.id })
          return result(:failed, 0, unmatched)
        end

        @catalog_year.update!(source: "pdf", base_url: url) if pdf_only?
        matched.each { |program, plans| write(program, plans, digest, url) }
        CatalogYearCourses.call(@catalog_year, matched.values.flatten(1).map(&:plan)) if pdf_only?
        ProgramPlanItem.link_catalog_courses
        # SharedElectives (in PlanWriter) adds the English sequence courses.
        ElectiveGroupCourse.link_catalog_courses
        AcademicProfiles::ProgramMatcher.relink_active
        @catalog_year.update!(status: "imported", imported_at: Time.current) if pdf_only?

        result(:imported, matched.size, unmatched).tap do |done|
          log("#{done.programs} programs: #{done.updated} updated, #{done.unchanged} unchanged, #{unmatched.size} with no match")
        end
      end

      private

      def start_year = @catalog_year.start_year

      def pdf_only? = PdfCatalog.pdf_only?(start_year)

      def two_columns? = PdfCatalog::LAYOUTS[start_year] == :courseleaf

      def parse(text)
        parser = PdfCatalog.parser_for(start_year)
        # The list catalogs print no credits for most rows.
        parser == ListParser ? parser.call(text, credits: KnownCredits.call(start_year)) : parser.call(text)
      end

      def result(status, programs, unmatched)
        Result.new(status: status, programs: programs, updated: @stats[:updated], unchanged: @stats[:unchanged],
                   unmatched: unmatched)
      end

      # { DegreeProgram => [PdfCatalog::Program, ...] } and the titles with no
      # match. A program the PDF prints twice keeps the first copy of each plan.
      def match(programs)
        matcher = @matcher || ProgramMatcher.new
        unmatched = []
        matched = programs.each_with_object({}) do |program, by_program|
          degree_program = matcher.call(program)
          if degree_program.nil?
            unmatched << (program.title || "untitled plan on page #{program.page}")
            next
          end

          list = (by_program[degree_program] ||= [])
          list << program unless list.any? { |other| other.plan.name == program.plan.name }
        end
        [ matched, unmatched.uniq ]
      end

      def write(degree_program, programs, digest, url)
        set = RequirementSet.find_or_initialize_by(degree_program: degree_program, catalog_year: @catalog_year)
        # A set from the catalog site or the Wayback Machine is better data.
        return if set.persisted? && !set.source_pdf?

        now = Time.current
        if set.persisted? && set.source_digest == digest
          set.update_columns(last_seen_at: now)
          @stats[:unchanged] += 1
          return
        end

        plans = programs.map(&:plan)
        attributes = { name: programs.first.title, path: "/previous-catalogs/#{url.split('/').last}#page=#{programs.first.page}",
                       total_credits: plans.first.total_credits, source: "pdf", source_digest: digest, fetched_at: now,
                       last_seen_at: now }
        if set.persisted? && stored_plans(set) == plans.map { |plan| plan_row(plan) }
          set.update!(attributes)
          @stats[:unchanged] += 1
          return
        end

        RequirementSet.transaction do
          set.update!(attributes.merge(needs_review: true, reviewed_at: nil))
          PlanWriter.call(set, plans: plans, groups: [])
        end
        @stats[:updated] += 1
      end

      def stored_plans(set) = set.program_plans.includes(:items).map { |plan| plan_row(plan) }

      # The values of a plan that a review checks, from a parsed plan or a
      # saved one.
      def plan_row(plan)
        [ plan.name, plan.years, plan.accelerated, plan.total_credits,
          plan.items.map do |item|
            [ item.year_index, item.season, item.kind, item.subject_code, item.course_number, item.label.presence,
              item.min_credits, item.max_credits, item.footnote, item.options ]
          end ]
      end

      def log(message)
        Rails.logger.info("[DegreeRequirements::PdfCatalog::Importer] #{@catalog_year.name}: #{message}")
      end
    end
  end
end
