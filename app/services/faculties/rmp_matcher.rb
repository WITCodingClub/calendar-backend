# frozen_string_literal: true

module Faculties
  # Finds the RateMyProfessors teacher that is the same person as a faculty
  # member. Students add teachers to RateMyProfessors by hand, so the names
  # differ from the WIT directory: "Muhammed" for "Muhammad", "Bill" for
  # "William", a middle name in place of the first name, or one half of a
  # hyphenated last name.
  #
  # A wrong link shows one professor's reviews on another professor's page, so
  # the rules are strict. Only one of the two names can differ, and only in a
  # way that keeps it the same name: a known nickname or a changed vowel inside
  # a long name. "John" and "Joan", "Daniel" and "Daniela", or "Chen" and "Chan"
  # never match. When the match is not clear, the matcher returns nil and an
  # admin decides on the Missing RMP IDs page.
  class RmpMatcher
    EXACT = 1.0
    MIN_SCORE = 0.85

    VOWELS = "aeiouy"

    # Words that many unrelated last names share.
    PARTICLES = %w[van von der den de del della da di du la le los las st san bin ibn al el jr sr ii iii iv].freeze

    NICKNAMES = {
      "william"     => %w[bill will billy liam],
      "robert"      => %w[bob bobby rob],
      "richard"     => %w[dick rick rich],
      "michael"     => %w[mike mick],
      "james"       => %w[jim jimmy jamie],
      "john"        => %w[jack],
      "christopher" => %w[chris],
      "daniel"      => %w[dan danny],
      "matthew"     => %w[matt],
      "nicholas"    => %w[nick],
      "benjamin"    => %w[ben],
      "samuel"      => %w[sam],
      "jonathan"    => %w[jon],
      "timothy"     => %w[tim],
      "andrew"      => %w[andy drew],
      "zachary"     => %w[zach],
      "jeffrey"     => %w[jeff],
      "gregory"     => %w[greg],
      "kenneth"     => %w[ken],
      "ronald"      => %w[ron],
      "donald"      => %w[don],
      "joseph"      => %w[joe joey],
      "thomas"      => %w[tom tommy],
      "steven"      => %w[steve],
      "stephen"     => %w[steve],
      "anthony"     => %w[tony],
      "edward"      => %w[ed ted ned],
      "theodore"    => %w[ted teddy],
      "charles"     => %w[chuck charlie],
      "alexander"   => %w[alex],
      "francis"     => %w[frank],
      "lawrence"    => %w[larry],
      "margaret"    => %w[peggy maggie meg],
      "elizabeth"   => %w[liz beth betsy],
      "katherine"   => %w[kate kathy katie],
      "catherine"   => %w[kate cathy katie],
      "jennifer"    => %w[jen jenny],
      "patricia"    => %w[pat patty trish],
      "rebecca"     => %w[becky],
      "susan"       => %w[sue],
      "deborah"     => %w[deb debbie],
      "victoria"    => %w[vicky tori],
      "abigail"     => %w[abby]
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
      }.filter_map { |edge| edge["node"] }
       .select { |node| node.dig("school", "id") == RateMyProfessorClient::WENTWORTH_SCHOOL_ID }
       .uniq { |node| node["id"] }
    end

    # The teacher node to link, or nil when the match is not clear. An exact
    # name wins over close spellings. A close spelling must be the only
    # candidate that qualifies. A teacher that another faculty member already
    # has still counts as a candidate, so a weaker one does not win in its place.
    def best_match(nodes = candidates)
      qualified = nodes.map { |node| [ node, score(node) ] }
                       .select { |_, value| value >= MIN_SCORE }
                       .sort_by { |_, value| -value }
      return if qualified.empty?

      top, top_score = qualified.first
      clear = top_score == EXACT ? qualified.count { |_, value| value == EXACT } == 1 : qualified.size == 1
      return unless clear
      return if Faculty.where(rmp_id: top["id"]).where.not(id: @faculty.id).exists?

      top
    end

    # 1.0 for the same name. Lower when one of the two names differs in an
    # allowed way. Below MIN_SCORE when both names differ.
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
      return 0.9 if significant(ours).intersect?(significant(theirs))
      return 0.85 if spelling_variant?(ours.join, theirs.join)

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
      return 0.85 if spelling_variant?(ours, theirs)

      0.0
    end

    def nickname?(a, b)
      NICKNAMES.fetch(a, []).include?(b) || NICKNAMES.fetch(b, []).include?(a)
    end

    # Two spellings of one name: the same length of 6 or more letters, and
    # only vowels differ, never the last letter. "Muhammad", "Muhammed", and
    # "Mohammad" match. "Antonio" and "Antonia" differ in the last letter, and
    # "Andrew" and "Andrea" differ in a consonant, so they do not.
    def spelling_variant?(a, b)
      return false if a.length != b.length || a.length < 6 || a[-1] != b[-1]

      diffs = a.chars.zip(b.chars).reject { |x, y| x == y }
      diffs.size.between?(1, a.length >= 8 ? 2 : 1) && diffs.flatten.all? { |c| VOWELS.include?(c) }
    end

    def significant(tokens)
      tokens.reject { |token| token.length < 3 || PARTICLES.include?(token) }
    end

    def tokens(name)
      I18n.transliterate(name.to_s).downcase.delete("'’.").split(/[^a-z]+/).reject(&:empty?)
    end
  end
end
