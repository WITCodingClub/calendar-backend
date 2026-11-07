# frozen_string_literal: true

module DegreeRequirements
  # Moves the program of an old catalog slug into the program of its new
  # slug (DegreeProgram::RENAMED_SLUGS): its catalog years, the pathway
  # steps, the student program links, and the concentrations. Then it
  # deletes the old program, which has no rows left.
  #
  # The two programs must not have a set for the same catalog year. The
  # merge stops and changes nothing if they do, because a person must choose
  # which set to keep.
  class ProgramMerge
    Result = Data.define(:status, :moved_sets)

    def self.call(old_slug, new_slug) = new(old_slug, new_slug).call

    def initialize(old_slug, new_slug)
      @old_slug = old_slug
      @new_slug = new_slug
    end

    def call
      old = DegreeProgram.find_by(slug: @old_slug)
      return Result.new(status: :nothing, moved_sets: 0) if old.nil?

      current = DegreeProgram.find_by(slug: @new_slug)
      if current.nil?
        old.update!(slug: @new_slug)
        return Result.new(status: :renamed, moved_sets: 0)
      end

      DegreeProgram.transaction do
        both = old.requirement_sets.where(catalog_year_id: current.requirement_sets.select(:catalog_year_id))
        if both.exists?
          years = both.joins(:catalog_year).pluck("catalog_years.start_year").sort.join(", ")
          raise Error, "#{@old_slug} and #{@new_slug} both have a set for #{years}"
        end

        moved = old.requirement_sets.update_all(degree_program_id: current.id, updated_at: Time.current)
        ProgramPathwayStep.where(degree_program_id: old.id).update_all(degree_program_id: current.id)
        # Only the catalog link changes. The scraped rows stay as they are.
        StudentProgram.where(degree_program_id: old.id).update_all(degree_program_id: current.id)
        DegreeProgram.where(parent_program_id: old.id).update_all(parent_program_id: current.id)
        old.reload.destroy!
        Result.new(status: :merged, moved_sets: moved)
      end
    end
  end
end
