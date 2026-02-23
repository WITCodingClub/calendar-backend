# frozen_string_literal: true

# Parses prerequisite rule strings into a structured AST (hash tree).
#
# Examples:
#   "COMP 1000"                          => {type: "course", code: "COMP1000"}
#   "COMP 1000 and MATH 2300"            => {type: "and", operands: [...]}
#   "COMP 1000 or COMP 1050"             => {type: "or", operands: [...]}
#   "COMP 1000 and (MATH 2300 or MATH 2100)" => nested structure
#   "Grade of C or better in COMP 1000"  => {type: "course", code: "COMP1000", min_grade: "C"}
#   "Permission of instructor"           => {type: "special", description: "Permission of instructor"}
class PrerequisiteParserService < ApplicationService
  # Matches patterns like "COMP 1000" or "COMP1000" (2-4 letters + 4 digits)
  COURSE_CODE_PATTERN = /\b([A-Z]{2,4})\s*(\d{4})\b/

  # Grade extraction: "Grade of C or better", "grade of B+", etc.
  GRADE_OF_PATTERN = /grade\s+of\s+([A-Fa-f][+-]?)\s+or\s+better\s+in\s+/i

  # Inline grade: "COMP 1000 with a grade of C or better"
  INLINE_GRADE_PATTERN = /\s+with\s+a\s+grade\s+of\s+([A-Fa-f][+-]?)\s+or\s+better/i

  # Minimum grade from prefix format
  MIN_GRADE_PREFIX_PATTERN = /^grade\s+of\s+([A-Fa-f][+-]?)\s+or\s+better\s+in\s+/i

  def initialize(rule_text:)
    @rule_text = rule_text
    super()
  end

  def call
    parse(@rule_text.strip)
  end

  private

  # Main entry point for recursive parsing.
  # Returns a hash AST node.
  def parse(text)
    text = text.strip

    return { type: "special", description: text } if special_requirement?(text)

    # Handle parenthesized groups at the top level before splitting on and/or
    tokens = tokenize(text)
    build_ast(tokens)
  end

  # Detects "Permission of instructor" style requirements that cannot be auto-validated.
  def special_requirement?(text)
    text.match?(/\bpermission\b/i) ||
      text.match?(/\bconsent\b/i) ||
      text.match?(/\binstructor\b.*\bapproval\b/i)
  end

  # Tokenizes the input into a flat list of tokens:
  #   :and, :or, course nodes, and nested group tokens.
  # Handles parentheses by recursively parsing sub-expressions.
  def tokenize(text)
    tokens = []
    i = 0
    chars = text.chars

    while i < chars.length
      if chars[i] == "("
        # Find matching closing paren
        depth = 1
        j = i + 1
        while j < chars.length && depth > 0
          depth += 1 if chars[j] == "("
          depth -= 1 if chars[j] == ")"
          j += 1
        end
        inner = chars[(i + 1)..(j - 2)].join
        tokens << parse(inner)
        i = j
      else
        remaining = chars[i..].join
        if (m = remaining.match(/\A\s*and\s+/i))
          tokens << :and
          i += m[0].length
        elsif (m = remaining.match(/\A\s*or\s+/i))
          tokens << :or
          i += m[0].length
        elsif (m = remaining.match(MIN_GRADE_PREFIX_PATTERN))
          # "Grade of C or better in COMP 1000 ..."
          min_grade = m[1].upcase
          remaining_after = remaining[m[0].length..]
          course_match = remaining_after.match(COURSE_CODE_PATTERN)
          if course_match
            code = normalize_code(course_match[1], course_match[2])
            node = { type: "course", code: code, min_grade: min_grade }
            tokens << node
            i += m[0].length + course_match.end(0)
          else
            i += 1
          end
        elsif (m = remaining.match(/\A\s*(#{COURSE_CODE_PATTERN.source})/))
          subject = m[2]
          number = m[3]
          code = normalize_code(subject, number)

          # Check for inline grade: "COMP 1000 with a grade of C or better"
          after_course = remaining[m[0].length..]
          node = { type: "course", code: code }
          if (gm = after_course.match(/\A#{INLINE_GRADE_PATTERN.source}/i))
            node[:min_grade] = gm[1].upcase
            i += m[0].length + gm[0].length
          else
            i += m[0].length
          end
          tokens << node
        else
          i += 1
        end
      end
    end

    tokens
  end

  # Builds an AST from a flat token list by collapsing :and and :or operators.
  # Precedence: AND binds tighter than OR.
  def build_ast(tokens)
    return { type: "special", description: "unknown" } if tokens.empty?

    # Filter out any nils
    tokens = tokens.compact

    # First pass: collapse AND groups
    and_groups = [[]]
    tokens.each do |tok|
      if tok == :and
        and_groups << []
      elsif tok == :or
        and_groups << :or_marker
        and_groups << []
      else
        and_groups.last << tok
      end
    end

    # Build each AND segment
    segments = []
    and_groups.each do |segment|
      next if segment == :or_marker

      segments << build_and_node(segment)
    end

    # Identify OR markers between segments
    # Rebuild with OR structure
    has_or = and_groups.include?(:or_marker)

    valid_segments = segments.compact

    if has_or
      return valid_segments.first if valid_segments.length == 1

      { type: "or", operands: valid_segments }
    else
      return { type: "special", description: "unknown" } if valid_segments.empty?
      return valid_segments.first if valid_segments.length == 1

      { type: "and", operands: valid_segments }
    end
  end

  def build_and_node(items)
    return nil if items.empty?
    return items.first if items.length == 1

    { type: "and", operands: items }
  end

  def normalize_code(subject, number)
    "#{subject.upcase}#{number}"
  end

end
