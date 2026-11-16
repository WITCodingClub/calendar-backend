# frozen_string_literal: true

module UniversityCalendar
  # Finds a feed event that repeats another one under a slightly different
  # title, on the same days and in the same category. The 25Live feed lists one
  # event once per organization that posts it ("Wellbeing Day" from one office,
  # "Campus Wellbeing Day - No Classes" from another).
  module DuplicateMatcher
    # The office whose copy wins. Every other organization has priority 0.
    ORGANIZATION_PRIORITY = {
      "Registrar's Office"  => 100,
      "Academic Affairs"    => 90,
      "Student Affairs"     => 80,
      "Center for Wellness" => 70
    }.freeze

    # Two titles with a score at or above this are the same event. 0.4 matches
    # titles that share their main words ("Wellbeing Day" and "Campus
    # Wellbeing Day") but not titles that share only one short word.
    SIMILARITY_THRESHOLD = 0.4

    STOPWORDS = %w[the a an and or but in on at to for of no].freeze

    module_function

    def similar?(title, other) = similarity(title, other) >= SIMILARITY_THRESHOLD

    # 0.0 (nothing in common) to 1.0 (the same). The shared words count 70%,
    # so a different word order or an added word still matches. The edit
    # distance counts 30%.
    def similarity(str1, str2)
      return 1.0 if str1 == str2
      return 0.0 if str1.nil? || str2.nil?

      s1 = str1.downcase.strip
      s2 = str2.downcase.strip
      return 1.0 if s1 == s2

      tokens1 = tokenize(s1)
      tokens2 = tokenize(s2)
      union   = (tokens1 | tokens2).size
      return 0.0 if union.zero?

      token_similarity = (tokens1 & tokens2).size.to_f / union
      max_length       = [ s1.length, s2.length ].max
      char_similarity  = 1.0 - (levenshtein_distance(s1, s2).to_f / max_length)

      (token_similarity * 0.7) + (char_similarity * 0.3)
    end

    def tokenize(str)
      str.gsub(/[^\w\s]/, " ").split(/\s+/).reject { |t| t.length < 2 || STOPWORDS.include?(t) }
    end

    def levenshtein_distance(str1, str2)
      return str2.length if str1.empty?
      return str1.length if str2.empty?

      matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }
      (0..str1.length).each { |i| matrix[i][0] = i }
      (0..str2.length).each { |j| matrix[0][j] = j }

      (1..str1.length).each do |i|
        (1..str2.length).each do |j|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1
          matrix[i][j] = [ matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost ].min
        end
      end

      matrix[str1.length][str2.length]
    end

    # The copy to keep: the office with the highest priority, then the one
    # fetched last (more likely current), then the oldest row.
    def preferred_event(events)
      events.max_by do |event|
        [
          ORGANIZATION_PRIORITY.fetch(event.organization, 0),
          event.last_fetched_at || Time.zone.at(0),
          -event.created_at.to_i
        ]
      end
    end
  end
end
