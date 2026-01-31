# frozen_string_literal: true

# Provides fuzzy duplicate detection for university calendar events
# Handles cases where events have similar (but not identical) titles
# and occur on the same day with the same category
module FuzzyDuplicateDetector
  extend ActiveSupport::Concern

  # Organization priority for deduplication
  # Higher priority organizations are preferred when resolving duplicates
  ORGANIZATION_PRIORITY = {
    "Registrar's Office"  => 100,
    "Academic Affairs"    => 90,
    "Student Affairs"     => 80,
    "Center for Wellness" => 70
    # All other organizations default to priority 0
  }.freeze

  # Similarity threshold for fuzzy matching (0.0 - 1.0)
  # Events with similarity >= this threshold are considered duplicates
  # 0.4 (40%) works well with token-based matching where events share
  # significant keywords like "Wellbeing Day" vs "Campus Wellbeing Day"
  # Lower threshold catches events with good token overlap but some character differences
  SIMILARITY_THRESHOLD = 0.4

  class_methods do
    # Find fuzzy duplicates for a given event
    # @param summary [String] Event summary to match
    # @param start_time [Time] Event start time
    # @param end_time [Time] Event end time
    # @param category [String] Event category
    # @param exclude_uid [String, nil] UID to exclude from results
    # @return [Array<UniversityCalendarEvent>] Matching events
    def find_fuzzy_duplicates(summary:, start_time:, end_time:, category:, exclude_uid: nil)
      # Find events on the same day with the same category
      # Use date range comparison instead of DATE() SQL function for better timezone handling
      start_date = start_time.to_date
      end_date = end_time.to_date

      candidates = where(category: category)
                   .where(start_time: start_date.beginning_of_day...(start_date.end_of_day + 1.second))
                   .where(end_time: end_date.beginning_of_day...(end_date.end_of_day + 1.second))

      candidates = candidates.where.not(ics_uid: exclude_uid) if exclude_uid

      # Filter by similarity threshold
      candidates.select do |event|
        similarity(summary, event.summary) >= SIMILARITY_THRESHOLD
      end
    end

    # Calculate string similarity using token-based matching and Levenshtein distance
    # This works better for event names which may have different word orders or additions
    # Returns a value between 0.0 (completely different) and 1.0 (identical)
    # @param str1 [String] First string
    # @param str2 [String] Second string
    # @return [Float] Similarity score
    def similarity(str1, str2)
      return 1.0 if str1 == str2
      return 0.0 if str1.nil? || str2.nil?

      # Normalize strings
      s1 = str1.downcase.strip
      s2 = str2.downcase.strip

      return 1.0 if s1 == s2

      # Use token-based similarity (Jaccard coefficient with token overlap)
      # This catches "Wellbeing Day" vs "Campus Wellbeing Day" more effectively
      tokens1 = tokenize(s1)
      tokens2 = tokenize(s2)

      # Calculate Jaccard similarity (intersection / union)
      intersection = (tokens1 & tokens2).size
      union = (tokens1 | tokens2).size

      return 0.0 if union.zero?

      token_similarity = intersection.to_f / union

      # Also calculate character-level similarity for additional matching
      distance = levenshtein_distance(s1, s2)
      max_length = [s1.length, s2.length].max
      char_similarity = max_length.zero? ? 0.0 : 1.0 - (distance.to_f / max_length)

      # Weight token similarity more heavily (70%) than character similarity (30%)
      # This makes "Campus Wellbeing Day" and "Wellbeing Day - No Classes" match
      # because they share significant tokens ("wellbeing", "day")
      (token_similarity * 0.7) + (char_similarity * 0.3)
    end

    # Tokenize a string into normalized words
    # Removes common stopwords and normalizes whitespace/punctuation
    # @param str [String] String to tokenize
    # @return [Array<String>] Array of tokens
    def tokenize(str)
      # Remove punctuation and split on whitespace
      tokens = str.gsub(/[^\w\s]/, " ").split(/\s+/)

      # Filter out common stopwords and very short tokens
      stopwords = %w[the a an and or but in on at to for of no]
      tokens.reject { |t| t.length < 2 || stopwords.include?(t) }
    end

    # Calculate Levenshtein distance between two strings
    # @param str1 [String] First string
    # @param str2 [String] Second string
    # @return [Integer] Edit distance
    def levenshtein_distance(str1, str2)
      # Handle edge cases
      return str2.length if str1.empty?
      return str1.length if str2.empty?

      # Build distance matrix
      matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }

      # Initialize first row and column
      (0..str1.length).each { |i| matrix[i][0] = i }
      (0..str2.length).each { |j| matrix[0][j] = j }

      # Fill in the rest of the matrix
      (1..str1.length).each do |i|
        (1..str2.length).each do |j|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1
          matrix[i][j] = [
            matrix[i - 1][j] + 1,      # deletion
            matrix[i][j - 1] + 1,      # insertion
            matrix[i - 1][j - 1] + cost # substitution
          ].min
        end
      end

      matrix[str1.length][str2.length]
    end

    # Determine which event to keep when resolving duplicates
    # Priority order:
    # 1. Organization priority (higher is better)
    # 2. Most recently fetched (more likely to be current)
    # 3. Oldest created (was in the system first)
    # @param events [Array<UniversityCalendarEvent>] Events to compare
    # @return [UniversityCalendarEvent] Event to keep
    def preferred_event(events)
      events.max_by do |event|
        [
          organization_priority(event.organization),
          event.last_fetched_at || Time.zone.at(0),
          -event.created_at.to_i # Negative to prefer older
        ]
      end
    end

    # Get priority score for an organization
    # @param organization [String, nil] Organization name
    # @return [Integer] Priority score
    def organization_priority(organization)
      ORGANIZATION_PRIORITY.fetch(organization, 0)
    end
  end

  # Instance method: check if this event is a fuzzy duplicate of another
  # @param other [UniversityCalendarEvent] Event to compare with
  # @return [Boolean] True if events are fuzzy duplicates
  def fuzzy_duplicate_of?(other)
    return false if self == other
    return false if category != other.category
    return false if start_time.to_date != other.start_time.to_date
    return false if end_time.to_date != other.end_time.to_date

    self.class.similarity(summary, other.summary) >= SIMILARITY_THRESHOLD
  end
end
