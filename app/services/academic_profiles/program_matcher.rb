# frozen_string_literal: true

module AcademicProfiles
  # Links student programs to the degree catalog (#526): the DegreeProgram
  # with the same subject and kind, and the CatalogYear of the catalog term.
  #
  # LeopardWeb names a program by its subject ("Computer Science") and gives
  # the degree apart ("Bachelor of Science"). The catalog puts both in the name
  # ("Computer Science, B.S.", "Computer Networking Minor"). The matcher
  # compares the subject only, and uses the role and degree to pick the kind.
  # A program with no match, or with more than one, keeps a null link.
  #
  # AcademicProfiles::Sync calls it for each payload. Run relink_active after
  # a degree catalog import, so programs saved before the import get a link.
  class ProgramMatcher < ApplicationService
    KINDS_BY_ROLE = {
      "major"         => %w[associate bachelor master exploratory],
      "minor"         => %w[minor],
      "concentration" => %w[concentration],
      "certificate"   => %w[certificate]
    }.freeze
    KIND_WORDS = /\b(minor|concentration|certificate)\b/i

    def self.relink_active
      StudentProgram.active.find_in_batches { |programs| new(programs).call }
    end

    def initialize(programs)
      @programs = programs
      super()
    end

    def call
      return if @programs.empty?

      degree_programs = DegreeProgram.where(kind: @programs.flat_map { |program| kinds_for(program) }.uniq).to_a
                                     .group_by { |degree_program| subject(degree_program.name) }
      catalog_years = CatalogYear.where(start_year: @programs.filter_map { |program| start_year(program) }.uniq)
                                 .index_by(&:start_year)

      @programs.each do |program|
        candidates = degree_programs.fetch(subject(program.name), []).select do |degree_program|
          kinds_for(program).include?(degree_program.kind)
        end

        program.update!(degree_program: (candidates.first if candidates.one?),
                        catalog_year:   catalog_years[start_year(program)])
      end
    end

    private

    # "Computer Science, B.S." and "Computer Science (BS)" give
    # "computer science".
    def subject(name)
      name.to_s.split(/[,(]/).first.to_s.gsub(KIND_WORDS, " ").downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def kinds_for(program)
      kinds = KINDS_BY_ROLE.fetch(program.role)
      return kinds unless program.major?

      case program.degree.to_s
      when /\Aassociate/i then %w[associate]
      when /\Abachelor/i then %w[bachelor]
      when /\Amaster/i then %w[master]
      else kinds
      end
    end

    # A catalog year starts in the fall, so the code 202620 (Spring 2026) is in
    # 2025-2026.
    def start_year(program)
      program.catalog_term_uid && ((program.catalog_term_uid / 100) - 1)
    end
  end
end
