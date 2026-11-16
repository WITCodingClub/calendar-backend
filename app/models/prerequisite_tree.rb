# frozen_string_literal: true

# The prerequisites of a course, as Catalog::CourseDetailsParser writes them
# to CatalogCourse#prerequisites. Each node is a Hash:
#   { "type" => "and" | "or", "operands" => [...] }
#   { "type" => "course", "subject_code" => "COMP", "course_number" => 1050, "min_grade" => "C", "level" => "Undergraduate" }
#   { "type" => "test", "name" => "WIT Math Assessment", "score" => "1500" }
#
# Every reader of the tree walks it through this object, so a new node type
# changes this file and the readers that give it a meaning.
class PrerequisiteTree
  GROUPS = %w[and or].freeze

  attr_reader :root

  # root: the tree, or nil for a course with no prerequisites.
  def initialize(root)
    @root = root
  end

  # The course nodes, in tree order.
  def courses
    nodes(root).select { |node| node["type"] == "course" }
  end

  # [subject_code, course_number] of each course the tree names, once each.
  def codes
    courses.map { |node| [ node["subject_code"].to_s.upcase, node["course_number"].to_i ] }.uniq
  end

  # [subject_code, course_number, required] for each course the tree names.
  # A course is required when no "or" with another choice is above it. A test
  # is not a course, but it counts as a choice in an "or".
  def requirements(node = root, required: true)
    return [] if node.nil?

    case node["type"]
    when "course" then [ [ node["subject_code"].to_s.upcase, node["course_number"].to_i, required ] ]
    when "and"    then operands(node).flat_map { |operand| requirements(operand, required: required) }
    when "or"     then operands(node).flat_map { |operand| requirements(operand, required: required && operands(node).size == 1) }
    else []
    end
  end

  # A copy of the tree with each course node replaced by the block's result.
  def map_courses(node = root, &block)
    return nil if node.nil?
    return node.merge("operands" => operands(node).map { |operand| map_courses(operand, &block) }) if node["operands"]

    node["type"] == "course" ? yield(node) : node
  end

  # Folds the tree from the leaves up. The block gets each node, the results
  # of its operands (empty for a leaf), and its depth (0 at the root).
  def fold(node = root, depth = 0, &block)
    return nil if node.nil?

    yield(node, operands(node).map { |operand| fold(operand, depth + 1, &block) }, depth)
  end

  def group?(node) = GROUPS.include?(node["type"])

  private

  def operands(node) = Array(node["operands"])

  def nodes(node)
    return [] if node.nil?

    [ node, *operands(node).flat_map { |operand| nodes(operand) } ]
  end
end
