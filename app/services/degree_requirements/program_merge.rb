# frozen_string_literal: true

module DegreeRequirements
  # Moves the program of an old catalog slug into the program of its new
  # slug (DegreeProgram::RENAMED_SLUGS): its catalog years, the pathway
  # steps, the student program links, and the concentrations. Then it
  # deletes the old program, which has no rows left.
  #
  # When both programs have a set for the same catalog year from the same
  # page (an import ran before the merge), the copy on the old program goes.
  # When the two sets differ, the merge stops and changes nothing, because a
  # person must choose which set to keep.
  class ProgramMerge
    Result = Data.define(:old_slug, :new_slug, :status, :moved_sets, :error)

    def self.call(old_slug, new_slug) = new(old_slug, new_slug).call

    # Merges every renamed program. A merge that stops is reported, and the
    # others still run.
    def self.renamed
      DegreeProgram::RENAMED_SLUGS.map do |old_slug, new_slug|
        call(old_slug, new_slug)
      rescue Error => e
        Rails.error.report(e, handled: true, context: { old_slug: old_slug, new_slug: new_slug })
        Result.new(old_slug: old_slug, new_slug: new_slug, status: :stopped, moved_sets: 0, error: e.message)
      end
    end

    def initialize(old_slug, new_slug)
      @old_slug = old_slug
      @new_slug = new_slug
    end

    def call
      old = DegreeProgram.find_by(slug: @old_slug)
      return result(:nothing) if old.nil?

      current = DegreeProgram.find_by(slug: @new_slug)
      if current.nil?
        old.update!(slug: @new_slug)
        return result(:renamed)
      end

      DegreeProgram.transaction do
        old.lock!
        drop_copies(old, current)
        moved = old.requirement_sets.update_all(degree_program_id: current.id, updated_at: Time.current)
        ProgramPathwayStep.where(degree_program_id: old.id).update_all(degree_program_id: current.id)
        # Only the catalog link changes. The scraped rows stay as they are.
        StudentProgram.where(degree_program_id: old.id).update_all(degree_program_id: current.id)
        DegreeProgram.where(parent_program_id: old.id).update_all(parent_program_id: current.id)
        # delete, not destroy: destroy would also delete a set that reached
        # the old program after the move. The foreign keys refuse that.
        old.delete
        result(:merged, moved)
      end
    end

    private

    def result(status, moved = 0)
      Result.new(old_slug: @old_slug, new_slug: @new_slug, status: status, moved_sets: moved, error: nil)
    end

    def drop_copies(old, current)
      kept = current.requirement_sets.index_by(&:catalog_year_id)
      old.requirement_sets.includes(:catalog_year).each do |set|
        other = kept[set.catalog_year_id]
        next if other.nil?

        if set.source_digest.nil? || set.source_digest != other.source_digest
          raise Error, "#{@old_slug} and #{@new_slug} both have a different set for #{set.catalog_year.start_year}"
        end

        set.destroy!
      end
    end
  end
end
