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
  class SectionLinks
    def initialize(course)
      @course = course
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
        partners = @course.is_section_linked ? @course.linked_sections.to_a : []
        partners.map { |partner| [ partner ] }
      end
    end

    # Banner can mark a section as linked and still give no partners (for
    # example COMP 1100 lab 21202 in Spring 2027). No partners means the
    # section stands alone.
    def required?
      banner? ? options.any? : @course.is_section_linked
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
  end
end
