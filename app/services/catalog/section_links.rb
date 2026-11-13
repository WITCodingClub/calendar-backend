# frozen_string_literal: true

module Catalog
  # The sections a student must register together with one section, for the
  # `linked` field of the section API, GraphQL, and MCP tools.
  #
  # Banner's own pairs (SectionLink rows from fetchLinkedSections) win once
  # they are fetched: source "banner". Before that, the old guess from link
  # identifiers applies (Course#linked_sections): source "link_identifier".
  # The identifiers can be wrong: in Spring 2027 they pair COMP 4960 lab 20455
  # with lecture 20451, but Banner pairs it with 20452.
  #
  # siblings: sections that are already in memory. When it is given, the
  # link identifier guess picks the partners from it (Course#link_partner?)
  # with no query. Catalog::ScheduleOptions loads every section of a course
  # in one query and passes them.
  class SectionLinks
    def initialize(course, siblings: nil)
      @course   = course
      @siblings = siblings
    end

    def banner?
      @course.links_fetched_at.present?
    end

    # @return [Array<Array<Course>>] each group is one set of partner sections
    def options
      @options ||= if banner?
        @course.section_links.sort_by { |link| [ link.option_group, link.linked_course.crn ] }
               .group_by(&:option_group).values.map { |links| links.map(&:linked_course) }
      else
        partners = @course.is_section_linked ? guessed_partners : []
        partners.map { |partner| [ partner ] }
      end
    end

    # Banner can mark a section as linked and still give no partners (for
    # example COMP 1100 lab 21202 in Spring 2027). No partners means the
    # section stands alone.
    def required?
      banner? ? options.any? : @course.is_section_linked
    end

    # True when the CRNs hold every section of one option group, or when the
    # section needs no partner (Catalog::ScheduleRules).
    def met_by?(crns)
      return true unless required?

      options.any? { |group| (group.map(&:crn) - crns).empty? }
    end

    def as_json(*)
      partners = options.flatten.uniq

      {
        required:   required?,
        identifier: @course.link_identifier,
        source:     banner? ? "banner" : "link_identifier",
        crns:       partners.map(&:crn),
        pub_ids:    partners.map(&:public_id),
        options:    options.map { |group| group.map(&:crn) }
      }
    end

    private

    def guessed_partners
      return @course.linked_sections.to_a if @siblings.nil?

      @siblings.select { |sibling| @course.link_partner?(sibling) }.sort_by(&:id)
    end
  end
end
