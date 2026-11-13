# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # Loads the sections of every requested course in one term and turns each
    # course entry into its units (Unit). It uses a fixed number of queries,
    # whatever the number of courses: the term, the aliases, the catalog
    # courses, the sections with their meetings and links, and the open seats.
    # The search then runs in memory.
    #
    # - A code matches the sections of that subject and number, and of each
    #   old or new code that a person checked (CourseCodeAlias.reviewed).
    # - A code that no catalog course has, and no checked alias leads to, is
    #   unknown: FilterError.
    # - A code with no active section in the term goes in not_offered. A
    #   course entry with no offered code is left out of the search.
    # - A pinned CRN must be a section of one of the entry's codes in the term,
    #   and not cancelled. The entry then keeps only the units that hold every
    #   pinned CRN.
    #   A pinned CRN can also be a linked partner of a section of the entry,
    #   such as the PHYS 1251 lab of a PHYS 1250 lecture.
    # - When the pinned CRNs of an entry are in no single unit, for example a
    #   lecture and a lab that Banner does not link, the pinned sections form
    #   one unit, if they keep Catalog::ScheduleRules together.
    # - A unit of lab sections only does not stand for a course that has an
    #   active lecture or another kind of section: a student takes the lab
    #   with it. A unit with a pinned CRN always stays.
    # - An entry whose sections are all linked partners in the units of an
    #   earlier entry (a PHYS 1251 lab entry next to a PHYS 1250 lecture
    #   entry) joins that entry: its units must hold one of those sections,
    #   and they must hold its pinned CRNs. Otherwise the lab would be in two
    #   entries, and no schedule could fit.
    class Candidates
      class TermNotFoundError < ::Catalog::FilterError; end

      LAB_TYPES = %w[laboratory online_sync_lab rotating_lab].freeze

      # A course entry with its units. index is its place in the request.
      # section_ids are the ids of its offered sections, pinned its pinned
      # sections.
      Entry = Data.define(:index, :units, :section_ids, :pinned)

      attr_reader :term, :entries, :not_offered

      def initialize(input)
        @input = input
      end

      def call
        @term = Term.find_by(uid: @input.term_uid) || raise(TermNotFoundError, "Unknown term_uid #{@input.term_uid}")
        check_known_codes!

        @not_offered = []
        @entries = merge_partner_entries(@input.entries.filter_map { |entry| build_entry(entry) })
        self
      end

      # The ids of the loaded sections with a free seat, by the open_only rule
      # of Catalog::SectionQuery. One query, only when open_only is set.
      def open_ids
        @open_ids ||= if @input.preferences.open_only
          SectionQuery.new(Course.where(id: pool.map(&:id))).call(open_only: true).pluck(:id).to_set
        else
          Set.new
        end
      end

      private

      def code_text((subject, number)) = "#{subject} #{number}"

      def check_known_codes!
        unknown = requested_codes.reject { |code| equivalents(code).any? { |other| known_codes.include?(other) } }
        raise FilterError, "Unknown course #{unknown.map { |code| code_text(code) }.join(', ')}" if unknown.any?
      end

      def requested_codes = @input.entries.flat_map(&:codes).uniq

      # A code and the old or new codes a person checked, both ways.
      def equivalents(code)
        [ code, *aliases.fetch(code, []) ].uniq
      end

      def aliases
        @aliases ||= begin
          numbers = requested_codes.map(&:last)
          CourseCodeAlias.reviewed
                         .where(from_course_number: numbers).or(CourseCodeAlias.reviewed.where(to_course_number: numbers))
                         .pluck(:from_subject_code, :from_course_number, :to_subject_code, :to_course_number)
                         .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(fs, fn, ts, tn), map|
                           map[[ fs, fn ]] << [ ts, tn ]
                           map[[ ts, tn ]] << [ fs, fn ]
                         end
        end
      end

      def all_codes = requested_codes.flat_map { |code| equivalents(code) }.uniq

      def known_codes
        @known_codes ||= CatalogCourse.where(course_number: all_codes.map(&:last).uniq)
                                      .pluck(:subject_code, :course_number).to_set
      end

      # Every section of the requested codes in the term, cancelled ones too,
      # so a pinned cancelled CRN gets a clear error. Partners of another
      # code come in through the links.
      def sections
        @sections ||= begin
          wanted = all_codes.to_set
          Course.where(term_id: term.id).where(code_clause)
                .includes({ meeting_times: { rooms: :building } },
                          section_links: { linked_course: [ { section_links: :linked_course },
                                                            { meeting_times: { rooms: :building } } ] })
                .order(:crn)
                .select { |course| wanted.include?(code_of(course)) }
        end
      end

      # The same subject match as Catalog::SectionQuery: the bare code or a
      # label that ends in "(CODE)". Course.prefix_of then checks each row.
      def code_clause
        clauses = all_codes.map { "(courses.course_number = ? AND (courses.subject = ? OR courses.subject ILIKE ?))" }
        binds   = all_codes.flat_map { |subject, number| [ number, subject, "%(#{subject})" ] }
        [ clauses.join(" OR "), *binds ]
      end

      def code_of(course) = [ Course.prefix_of(course.subject).upcase, course.course_number ]

      # The loaded sections by id, so a partner reached through a link is the
      # same object as the section loaded for its own code.
      def by_id
        @by_id ||= sections.index_by(&:id).tap do |map|
          sections.flat_map(&:section_links).each { |link| map[link.linked_course_id] ||= link.linked_course }
        end
      end

      def pool = by_id.values

      # The link identifier guess only pairs sections of the same course, so
      # each section gets the loaded sections of its own course as siblings.
      def links(course)
        @links ||= {}
        @links[course.id] ||= SectionLinks.new(course, siblings: siblings[[ course.subject, course.course_number ]])
      end

      def siblings
        @siblings ||= pool.group_by { |course| [ course.subject, course.course_number ] }
      end

      def slots(course)
        @slots ||= {}
        @slots[course.id] ||= ScheduleRules.meetings(course).map { |meeting| Slot.from(meeting) }
      end

      def build_entry(entry)
        codes   = entry.codes.map { |code| equivalents(code).to_set }
        offered = sections.select { |course| course.active? && codes.any? { |set| set.include?(code_of(course)) } }
        @not_offered.concat(entry.codes.each_with_index.filter_map do |code, index|
          code_text(code) if offered.none? { |course| codes[index].include?(code_of(course)) }
        end)

        pinned = pinned_sections(entry, offered)
        return nil if offered.empty?

        pinned_ids = pinned.map(&:id).to_set
        units = units_for(entry, offered, pinned_ids)
        if pinned.any?
          units = units.select { |unit| pinned.all? { |course| unit.crns.include?(course.crn) } }
          units = [ unit(entry, pinned.first, pinned.drop(1), pinned_ids) ].compact if units.empty?
        end
        Entry.new(index: entry.index, units: units, section_ids: offered.map(&:id).to_set, pinned: pinned)
      end

      # A pinned CRN is a section of the entry, or a linked partner of one.
      def pinned_sections(entry, offered)
        allowed = offered.map(&:id).to_set | offered.flat_map { |course| course.section_links.map(&:linked_course_id) }
        entry.crns.map do |crn|
          course = sections.find { |section| section.crn == crn && allowed.include?(section.id) } ||
                   pool.find { |section| section.crn == crn && allowed.include?(section.id) }
          if course.nil?
            cancelled = sections.find { |section| section.crn == crn && entry.codes.any? { |code| equivalents(code).include?(code_of(section)) } }
            raise FilterError, "CRN #{crn} is cancelled" if cancelled && !cancelled.active?

            names = entry.codes.map { |code| code_text(code) }.join(" or ")
            raise FilterError, "CRN #{crn} is not a section of #{names} in term #{term.uid}"
          end
          raise FilterError, "CRN #{crn} is cancelled" unless course.active?

          course
        end
      end

      def units_for(entry, offered, pinned_ids)
        units = offered.flat_map do |course|
          groups = links(course).required? ? links(course).options : [ [] ]
          groups.filter_map { |group| unit(entry, course, group, pinned_ids) }
        end
        units = units.uniq(&:crns)

        # Codes with an active section that is not a lab.
        with_lecture = offered.reject { |course| lab?(course) }.to_set { |course| code_text(code_of(course)) }
        units.reject do |unit|
          with_lecture.include?(unit.code) && unit.sections.all? { |course| lab?(course) } && unit.members.none?(&:pinned)
        end.sort_by(&:crns)
      end

      def lab?(course) = LAB_TYPES.include?(course.schedule_type)

      def merge_partner_entries(entries)
        entries.each_with_object([]) do |entry, kept|
          host = kept.find do |other|
            entry.section_ids.disjoint?(other.section_ids) &&
              entry.section_ids.subset?(other.units.flat_map { |unit| unit.sections.map(&:id) }.to_set)
          end
          next kept << entry if host.nil?

          units = host.units.select do |unit|
            unit.sections.any? { |course| entry.section_ids.include?(course.id) } &&
              entry.pinned.all? { |course| unit.crns.include?(course.crn) }
          end
          pinned_ids = entry.pinned.to_set(&:id)
          units = units.map { |unit| repin(unit, pinned_ids) } if pinned_ids.any?
          kept[kept.index(host)] = host.with(units: units, pinned: host.pinned + entry.pinned)
        end
      end

      # The unit with the joined entry's pinned sections marked as pinned, so
      # open_only keeps them.
      def repin(unit, pinned_ids)
        members = unit.members.map { |member| member.with(pinned: member.pinned || pinned_ids.include?(member.course.id)) }
        Unit.new(entry_index: unit.entry_index, code: unit.code, members: members)
      end

      # nil when the section and the group break a rule among themselves.
      def unit(entry, course, group, pinned_ids)
        sections = [ course, *group.map { |partner| by_id[partner.id] || partner } ].uniq(&:id)
        return nil unless sections.all?(&:active?)

        crns = sections.map(&:crn)
        return nil unless sections.all? { |section| links(section).met_by?(crns) }
        return nil unless sections.map { |section| ScheduleRules.duplicate_key(section) }.uniq.size == sections.size

        members = sections.map { |section| Member.new(course: section, slots: slots(section), pinned: pinned_ids.include?(section.id)) }
        conflict = members.combination(2).any? do |a, b|
          a.slots.any? { |x| b.slots.any? { |y| ScheduleRules.overlap?(x, y) } }
        end
        return nil if conflict

        Unit.new(entry_index: entry.index, code: code_text(code_of(course)), members: members)
      end
    end
  end
end
