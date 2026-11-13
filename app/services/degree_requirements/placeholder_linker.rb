# frozen_string_literal: true

module DegreeRequirements
  # Links each placeholder of a plan to the elective list it names, for a
  # program page (ProgramPageParser) and a catalog PDF (PdfCatalog::ElectiveLists).
  #
  # A placeholder such as "Computer Science Elective 1" names the list
  # "Computer Science Electives" of its own plan or of the whole program.
  # "NET Elective" names "The Computer Networking Electives" by its subject
  # code. A list of another plan with the same name is the last choice: a
  # second plan can print its list under a long note in place of a name.
  #
  # `plans` are ProgramPageParser::Plan and `groups` ProgramPageParser::Group.
  # When two lists match, the first one wins, so the caller puts the best
  # list first.
  module PlaceholderLinker
    # A code that names a shared list (HSS, FREE, ...) is left to
    # SharedElectives, and a list of two areas ("Math or Computer Science
    # Elective") never matches a code.
    SHARED_CODES = %w[hss hhs free gen open engl coop].freeze

    module_function

    def call(plans, groups)
      plans.each_with_index.map do |plan, plan_index|
        items = plan.items.map do |item|
          next item unless item.kind == "placeholder"

          own = groups.each_index.select { |i| groups[i].plan_index.in?([ nil, plan_index ]) }
          item.with(group_index: name_match(item.label, groups, own) || code_match(item.label, groups, own) ||
                                 name_match(item.label, groups, groups.each_index.to_a))
        end
        plan.with(items: items)
      end
    end

    def name_match(label, groups, indexes)
      key = match_key(label)
      return nil if key.blank?

      indexes.find do |i|
        group_key = match_key(groups[i].name)
        group_key.present? && (group_key.start_with?(key) || key.start_with?(group_key))
      end
    end

    # "BSCI Elective" and "Building Sciences Electives": the code is the
    # start of one word, or of each of a run of words. Only one list may
    # match.
    def code_match(label, groups, indexes)
      code = label.to_s[/\A([A-Z]{2,5})\s+electives?\b/i, 1]&.downcase
      return nil if code.nil? || SHARED_CODES.include?(code)

      found = indexes.reject { |i| groups[i].name.to_s.match?(/\bor\b/i) }
                     .select { |i| abbreviates?(code, name_words(groups[i].name)) }
      found.one? ? found.first : nil
    end

    def name_words(name)
      name.to_s.downcase.scan(/[a-z]+/) - %w[the electives elective and of in courses course list]
    end

    def abbreviates?(code, words)
      words.each_index.any? { |start| consumes?(code, words, start) }
    end

    def consumes?(code, words, index)
      return true if code.empty?
      return false if index >= words.size

      word = words[index]
      (1..[ code.size, word.size ].min).reverse_each.any? do |length|
        word.start_with?(code[0, length]) && consumes?(code[length..], words, index + 1)
      end
    end

    def match_key(text)
      text.to_s.downcase.sub(/\A[\s¹²³⁴⁵*†]*(?:the\s+)?/, "").sub(/[\s\d*†:]+\z/, "")
          .gsub(/electives?/, "elective").gsub(/[^a-z]/, "")
    end
  end
end
