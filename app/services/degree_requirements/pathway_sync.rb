# frozen_string_literal: true

module DegreeRequirements
  # Fills ProgramPathway and ProgramPathwayStep from two pages (#868), so no
  # person keeps a list:
  #
  # - The Accelerated Programs page of the current catalog. Each option with
  #   two or more programs and a bachelor's, such as the 5-year Architecture
  #   B.S. plus M.Arch, is a `combined` pathway with those steps.
  # - The Double Leopard page on wit.edu. Each master's program there is a
  #   `double_leopard` pathway. Its steps are the master's programs only: a
  #   senior in any bachelor's program can apply, so the student's own
  #   bachelor's is the first part (AcademicProfiles::PlannedPrograms).
  #
  # A Double Leopard name matches a master's program of the newest catalog
  # year by its subject: "Computer Science" is "Computer Science, M.S.". A
  # dual degree ("Architecture & Construction Management Dual Degree") is one
  # pathway with a step for each master's.
  #
  # The Importer runs it after an import of the current catalog, and `bin/rails
  # degree_requirements:pathways` runs it now. It is safe to run again.
  #
  # - A fetch error, or a page with no options, raises before any change, so
  #   the stored pathways stay as they are.
  # - A combined option with a program that is not imported yet is skipped
  #   and stays as it is. A Double Leopard name with no master's program is
  #   listed in Result#unmatched.
  # - A pathway that neither page lists is set inactive, not deleted, because
  #   planned programs link to it.
  class PathwaySync
    Result = Data.define(:saved, :skipped, :unmatched, :deactivated)

    # A page loaded but had none of the parts this class reads. The site
    # changed, so the stored pathways stay.
    class EmptySourceError < Error; end

    MASTER_WORDS = /\bmaster(?:'?s)?\s+(?:of\s+science|degree|of)\b|\bm\.\s?(?:s|arch|eng)\.?(?![a-z])|\bmasters?\b/i
    DUAL_DEGREE = /\s*dual\s+degree\s*\z/i

    # The subject of a master's program name, for matching:
    # "Computer Science, M.S.", "Architecture, M. Arch.", and "Master of
    # Architecture" give "computerscience" and "architecture".
    def self.subject_key(name)
      name.to_s.downcase.gsub(MASTER_WORDS, " ").gsub(/[^a-z0-9]/, "")
    end

    def initialize(client: CatalogSiteClient.new)
      @client = client
    end

    def call
      combined = AcceleratedProgramsParser.new(fetch!("#{SITE_URL}#{AcceleratedProgramsParser::PATH}")).entries
      raise EmptySourceError, "#{AcceleratedProgramsParser::PATH} lists no pathways" if combined.empty?

      leopard = DoubleLeopardParser.new(fetch!(DOUBLE_LEOPARD_URL))
      raise EmptySourceError, "#{DOUBLE_LEOPARD_URL} lists no programs" if leopard.names.empty?

      @saved = []
      @skipped = []
      @unmatched = []
      ProgramPathway.transaction do
        combined.each { |entry| sync_combined(entry) }
        leopard.names.each { |name| sync_double_leopard(name, leopard.max_shared_courses) }
      end

      deactivated = ProgramPathway.active.where.not(slug: @saved + @skipped).update_all(active: false, updated_at: Time.current)
      Result.new(saved: @saved, skipped: @skipped, unmatched: @unmatched, deactivated: deactivated)
    end

    private

    def fetch!(url)
      @client.get(url) || raise(FetchError, "GET #{url}: not found")
    end

    # An option of only master's programs, such as the M.Arch plus M.S. in
    # Construction Management, is on the Double Leopard page too, so it is
    # left out here.
    def sync_combined(entry)
      slug = entry.slugs.join("-and-")
      programs = DegreeProgram.where(slug: entry.slugs).index_by(&:slug)
      missing = entry.slugs - programs.keys
      if missing.any?
        @skipped << slug
        log("skipped #{slug}: no program #{missing.join(', ')} yet")
        return
      end

      steps = entry.slugs.map { |key| programs.fetch(key) }
      return unless steps.any?(&:bachelor?)

      save(slug: slug, name: entry.name, kind: "combined", max_shared_courses: nil, steps: steps)
    end

    def sync_double_leopard(name, max_shared_courses)
      steps = match_masters(name)
      if steps.nil?
        @unmatched << name
        log("no master's program for Double Leopard #{name.inspect}")
        return
      end

      label = steps.one? ? steps.first.name : name
      save(slug: "double-leopard-#{steps.map(&:slug).join('-and-')}", name: "#{label} (Double Leopard)",
           kind: "double_leopard", max_shared_courses: max_shared_courses, steps: steps)
    end

    # The master's programs for a Double Leopard name, or nil. The whole
    # name is tried first, so "Electrical and Computer Engineering" stays one
    # program. A dual degree splits at "&".
    def match_masters(name)
      whole = masters_by_subject[self.class.subject_key(name)]
      return [ whole ] if whole

      parts = name.sub(DUAL_DEGREE, "").split(/\s*&\s*/)
      return nil if parts.size < 2

      steps = parts.map { |part| masters_by_subject[self.class.subject_key(part)] }
      steps.all? ? steps : nil
    end

    # The master's programs of the newest catalog year with programs, by
    # subject. Two programs with the same subject match neither.
    def masters_by_subject
      @masters_by_subject ||= begin
        newest = RequirementSet.joins(:catalog_year).maximum("catalog_years.start_year")
        programs = DegreeProgram.master.where(id: RequirementSet.joins(:catalog_year)
                                                                .where(catalog_years: { start_year: newest })
                                                                .select(:degree_program_id))
        programs.group_by { |program| self.class.subject_key(program.name) }
                .filter_map { |key, list| [ key, list.first ] if list.one? }.to_h
      end
    end

    def save(slug:, name:, kind:, max_shared_courses:, steps:)
      pathway = ProgramPathway.find_or_initialize_by(slug: slug)
      pathway.update!(name: name, kind: kind, active: true, max_shared_courses: max_shared_courses, max_shared_credits: nil)
      @saved << slug

      wanted = steps.map(&:id)
      return if pathway.steps.map(&:degree_program_id) == wanted

      pathway.steps.delete_all
      wanted.each_with_index do |degree_program_id, index|
        pathway.steps.create!(degree_program_id: degree_program_id, position: index + 1)
      end
    end

    def log(message)
      Rails.logger.info("[DegreeRequirements::PathwaySync] #{message}")
    end
  end
end
