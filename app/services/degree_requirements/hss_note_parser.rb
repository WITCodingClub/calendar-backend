# frozen_string_literal: true

module DegreeRequirements
  # Reads what a major adds to the humanities and social science (HSS)
  # requirement, from the "ENGL/HSS Note" and the directed elective notes of
  # its program page. The subjects of each category are the same for every
  # major (SharedElectives). What differs:
  #
  # - the credit total for English, humanities, and social sciences (20 to 32)
  # - an Ethics course (Computer Science, Cybersecurity, IT, Networking, ...)
  # - directed courses: "must include the following: ECON4102 ... or ECON4152"
  # - a category of its own: "At least one elective in Art History (HUMN4243,
  #   ...)", "At least one elective in Psychology or Sociology"
  #
  # Each category asks for at least one course. Humanities and Social
  # Sciences are always there: the HSS requirement page asks every bachelor
  # for one of each. A category the page names with no courses, such as
  # "Design History", has no matcher, and degree progress cannot check it.
  #
  # Returns { "min_credits" => 20, "categories" => [{ "name", "subject_codes",
  # "courses" }] }. A course is "PHIL4501".
  class HssNoteParser
    # The Ethics courses that the Computer Networking page lists. The other
    # pages ask for "an Ethics elective" with no list.
    ETHICS_COURSES = %w[PHIL4401 PHIL4501 PHIL4525 PHIL4600].freeze
    # "Art History" and "Design History" are not HIST courses, so "history"
    # names no subject.
    SUBJECT_WORDS = { "psychology" => "PSYC", "sociology" => "SOCL", "economics" => "ECON", "philosophy" => "PHIL",
                      "literature" => "LITR", "communication" => "COMM" }.freeze

    CODE = /\b([A-Z]{4})\s?(\d{4})\b/
    MIN_CREDITS = /minimum of (\d+) credit(?:s| hours)?(?: total)?,? (?:in|including) English/i
    EXTRA_CATEGORY = /At least one (?:elective|course) in (?!Humanities|the Social|a Humanities|a Social)([^.;:]+?)(?:\(([^)]*)\))?\s*(?:[.;]|\z|At least|The remaining)/i
    ETHICS = /must include[^.]{0,80}\bEthics\b|must be an Ethics\b/i
    DIRECTED = /must include the following(?: HSS Directed Electives)?\s*:?(.{0,500})/i

    def self.default
      { "min_credits" => nil, "categories" => base_categories }
    end

    def self.base_categories
      [ { "name" => "Humanities", "subject_codes" => SharedElectives::HUMANITIES, "courses" => [] },
        { "name" => "Social Sciences", "subject_codes" => SharedElectives::SOCIAL_SCIENCES, "courses" => [] } ]
    end

    def initialize(html)
      @html = html.to_s
    end

    def call
      text = page_text
      categories = self.class.base_categories + extra_categories(text)
      categories << { "name" => "Ethics", "subject_codes" => [], "courses" => ethics_courses(text) } if text.match?(ETHICS)
      categories += directed_categories(text)

      { "min_credits" => text[MIN_CREDITS, 1]&.to_i, "categories" => categories.uniq { |category| category["name"] } }
    end

    private

    # The page text with the notes that CourseLeaf keeps in the onclick of a
    # footnote link ("\x3cp\x3e...").
    def page_text
      doc = Nokogiri::HTML(@html)
      node = doc.at_css("article#content") || doc.at_css("body") || doc
      notes = node.css("[onclick*='lfjs.bubble']").filter_map do |link|
        script = link["onclick"][/lfjs\.bubble\(this,\s*'(.*?)'\s*,/m, 1]
        script && spaced(Nokogiri::HTML.fragment(script.gsub(/\\x(\h{2})/) { Regexp.last_match(1).hex.chr }.gsub("\\'", "'")))
      end
      [ spaced(node), *notes.uniq ].join(" ")
    end

    # The text of each node with a space between, so table cells do not run
    # together ("ECON4102PRINCIPLES").
    def spaced(node)
      node.xpath(".//text()").map(&:text).join(" ").gsub(/[[:space:]]+/, " ").strip
    end

    def extra_categories(text)
      text.scan(EXTRA_CATEGORY).map do |name, codes|
        name = name.squish.delete_suffix(",")
        courses = codes.to_s.scan(CODE).map(&:join)
        subjects = courses.empty? ? name.downcase.scan(/\w+/).filter_map { |word| SUBJECT_WORDS[word] } : []
        { "name" => name, "subject_codes" => subjects, "courses" => courses }
      end.uniq { |category| category["name"].downcase }
    end

    def ethics_courses(text)
      # "PHIL4525 A.I. ETHICS or PHIL4600": the list has full stops in it.
      listed = text[/Ethics course:?(.{0,300}?)(?:ENGL\/HSS Note|\z)/i, 1].to_s.scan(CODE).map(&:join)
      listed.any? ? listed : ETHICS_COURSES
    end

    # "ECON4102 PRINCIPLES OF ECONOMICS 4 or ECON4152 MACROECONOMICS
    # PSYC4552 ...": a code after "or" is another choice for the same course.
    def directed_categories(text)
      segment = text[DIRECTED, 1].to_s.split(/\bAn Ethics elective\b|\bIn lieu\b|\bA minimum\b|\bco-op\b|ENGL\/HSS Note/i).first.to_s
      groups = []
      position = 0
      segment.to_enum(:scan, CODE).each do
        match = Regexp.last_match
        code = match[1] + match[2]
        between = segment[position...match.begin(0)]
        if groups.any? && between.match?(/\bor\s*\z/i)
          groups.last << code
        else
          groups << [ code ]
        end
        position = match.end(0)
      end
      groups.map { |codes| { "name" => "Directed: #{codes.first}", "subject_codes" => [], "courses" => codes.uniq } }
    end
  end
end
