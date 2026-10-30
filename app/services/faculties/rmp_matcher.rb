# frozen_string_literal: true

require "did_you_mean"

module Faculties
  # Finds the RateMyProfessors teacher that is the same person as a faculty
  # member. Students add teachers to RateMyProfessors by hand, so the names
  # differ from the WIT directory: "Muhammed" for "Muhammad", "Chris" for
  # "Christopher", a middle name in place of the first name, or one half of a
  # hyphenated last name.
  #
  # The matcher links a teacher only when exactly one candidate scores at or
  # above MIN_SCORE. A tie is a guess, so it returns nil and an admin decides on
  # the Missing RMP IDs page.
  class RmpMatcher
    MIN_SCORE = 0.75
    EXACT = 1.0

    # Short forms that are not a prefix of the full name. A prefix ("Chris",
    # "Dan") already matches without an entry here.
    NICKNAMES = {
      "william"   => %w[bill will billy liam],
      "robert"    => %w[bob bobby rob],
      "richard"   => %w[dick rick rich],
      "michael"   => %w[mike mick],
      "james"     => %w[jim jimmy],
      "john"      => %w[jack],
      "margaret"  => %w[peggy maggie meg],
      "elizabeth" => %w[liz beth betsy lisa],
      "katherine" => %w[kate kathy katie],
      "catherine" => %w[kate cathy katie],
      "edward"    => %w[ted ed ned],
      "theodore"  => %w[ted teddy],
      "charles"   => %w[chuck charlie],
      "anthony"   => %w[tony],
      "joseph"    => %w[joe joey],
      "thomas"    => %w[tom tommy],
      "steven"    => %w[steve],
      "stephen"   => %w[steve],
      "alexander" => %w[alex sasha],
      "francis"   => %w[frank],
      "henry"     => %w[hank],
      "lawrence"  => %w[larry],
      "patricia"  => %w[pat patty trish],
      "rebecca"   => %w[becky],
      "susan"     => %w[sue],
      "deborah"   => %w[deb debbie]
    }.freeze

    def initialize(faculty, client: RateMyProfessorClient.new)
      @faculty = faculty
      @client = client
    end

    # Teachers at WIT from a search for the full name and a search for the last
    # name alone. The full-name search misses a teacher whose first name is
    # spelled differently, and the last-name search finds that teacher.
    def candidates
      @candidates ||= [ @faculty.full_name, @faculty.last_name ].uniq.flat_map { |text|
        @client.search_professors(text, count: 20).dig("data", "newSearch", "teachers", "edges") || []
      }.map { |edge| edge["node"] }.compact.uniq { |node| node["id"] }
    end

    # The teacher node to link, or nil when no candidate is close enough or two
    # candidates are equally close.
    def best_match(nodes = candidates)
      taken = Faculty.where(rmp_id: nodes.map { |node| node["id"] }).where.not(id: @faculty.id).pluck(:rmp_id)
      scored = nodes.reject { |node| taken.include?(node["id"]) }
                    .map { |node| [ node, score(node) ] }
                    .select { |_, value| value >= MIN_SCORE }
                    .sort_by { |_, value| -value }

      return if scored.empty?
      return if scored.size > 1 && scored[0][1] == scored[1][1]

      scored.first.first
    end

    # 1.0 for the same name. Lower for a spelling or nickname difference in one
    # name. A difference in both names scores below MIN_SCORE.
    def score(node)
      last = last_name_score(node["lastName"])
      return 0.0 if last.zero?

      last * first_name_score(node["firstName"])
    end

    private

    def last_name_score(rmp_last)
      ours = tokens(@faculty.last_name)
      theirs = tokens(rmp_last)
      return 0.0 if ours.empty? || theirs.empty?
      return EXACT if ours.join == theirs.join
      # "Garcia-Lopez" in the directory and "Garcia" on RateMyProfessors.
      return 0.9 if ours.intersect?(theirs)
      return 0.8 if typo?(ours.join, theirs.join)

      0.0
    end

    # The directory first name, the display name, and the middle name are all
    # names the professor can go by.
    def first_name_score(rmp_first)
      theirs = tokens(rmp_first).first
      return 0.0 if theirs.nil?

      given_names.map { |ours| name_similarity(ours, theirs) }.max || 0.0
    end

    def given_names
      [ @faculty.first_name, @faculty.display_name.to_s.split.first, @faculty.middle_name ]
        .filter_map { |name| tokens(name).first }.uniq
    end

    def name_similarity(ours, theirs)
      return EXACT if ours == theirs
      return 0.9 if nickname?(ours, theirs)
      return 0.85 if typo?(ours, theirs)
      return 0.85 if [ ours, theirs ].min_by(&:length).length >= 3 && (ours.start_with?(theirs) || theirs.start_with?(ours))

      0.0
    end

    def nickname?(a, b)
      NICKNAMES.fetch(a, []).include?(b) || NICKNAMES.fetch(b, []).include?(a)
    end

    # One changed letter in a name of 4 or more letters, or two in a name of 8
    # or more. "Muhammad" and "Muhammed" are one letter apart.
    def typo?(a, b)
      shorter = [ a.length, b.length ].min
      return false if shorter < 4

      DidYouMean::Levenshtein.distance(a, b) <= (shorter >= 8 ? 2 : 1)
    end

    def tokens(name)
      I18n.transliterate(name.to_s).downcase.delete("'’.").split(/[^a-z]+/).reject(&:empty?)
    end
  end
end
