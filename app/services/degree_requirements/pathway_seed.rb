# frozen_string_literal: true

module DegreeRequirements
  # Fills ProgramPathway and ProgramPathwayStep from config/program_pathways.yml
  # (#868). People keep that file, because the catalog has no list of the
  # 3+1, 4+1, and 5-year pathways: its Accelerated Programs page names only
  # the 5-year Architecture path, and the Double Leopard list is on wit.edu.
  #
  # The Importer runs it after each catalog year, and `bin/rails
  # degree_requirements:pathways` runs it now. It is safe to run again.
  #
  # - A pathway with a program that is not imported yet is skipped. The next
  #   import adds it.
  # - A pathway that left the file is set inactive, not deleted, because
  #   planned programs link to it.
  class PathwaySeed
    PATH = Rails.root.join("config/program_pathways.yml")

    Result = Data.define(:saved, :skipped, :deactivated)

    # A file that does not parse, or an entry with no slug, name, kind, or
    # steps.
    class InvalidSeedError < StandardError; end

    def self.entries(path = PATH)
      data = YAML.safe_load_file(path)
      raise InvalidSeedError, "#{path} must be a list" unless data.is_a?(Array)

      data.each_with_index.map { |entry, index| normalize(entry, index) }
    rescue Psych::Exception => e
      raise InvalidSeedError, e.message
    end

    def self.normalize(entry, index)
      raise InvalidSeedError, "entry #{index}: must be a map" unless entry.is_a?(Hash)

      entry = entry.stringify_keys
      steps = Array(entry["steps"])
      raise InvalidSeedError, "entry #{index}: each step must be a map with a program" unless steps.all?(Hash)

      steps = steps.map(&:stringify_keys)
      missing = %w[slug name kind].select { |key| entry[key].blank? }
      missing << "steps" if steps.size < 2 || steps.any? { |step| step["program"].blank? }
      raise InvalidSeedError, "entry #{index}: needs #{missing.join(', ')}" if missing.any?

      entry.merge("steps" => steps)
    end
    private_class_method :normalize

    def initialize(path: PATH)
      @path = path
    end

    def call
      entries = self.class.entries(@path)
      saved = []
      skipped = []

      ProgramPathway.transaction do
        entries.each do |entry|
          programs = DegreeProgram.where(slug: entry["steps"].pluck("program")).index_by(&:slug)
          missing = entry["steps"].pluck("program") - programs.keys
          if missing.any?
            skipped << entry["slug"]
            log("skipped #{entry['slug']}: no program #{missing.join(', ')} yet")
            next
          end

          save(entry, programs)
          saved << entry["slug"]
        end
      end

      deactivated = ProgramPathway.active.where.not(slug: entries.pluck("slug")).update_all(active: false, updated_at: Time.current)
      Result.new(saved: saved, skipped: skipped, deactivated: deactivated)
    end

    private

    def save(entry, programs)
      pathway = ProgramPathway.find_or_initialize_by(slug: entry["slug"])
      pathway.update!(name: entry["name"], kind: entry["kind"], active: true,
                      max_shared_courses: entry["max_shared_courses"], max_shared_credits: entry["max_shared_credits"])

      wanted = entry["steps"].map { |step| [ programs.fetch(step["program"]).id, step["plan_years"] ] }
      return if pathway.steps.map { |step| [ step.degree_program_id, step.plan_years ] } == wanted

      pathway.steps.delete_all
      wanted.each_with_index do |(degree_program_id, plan_years), position|
        pathway.steps.create!(degree_program_id: degree_program_id, plan_years: plan_years, position: position + 1)
      end
    end

    def log(message)
      Rails.logger.info("[DegreeRequirements::PathwaySeed] #{message}")
    end
  end
end
