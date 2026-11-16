# frozen_string_literal: true

# Renders a prerequisite tree (PrerequisiteTree) as HTML for the dashboard
# course page and the admin course page. The block renders the link of one
# course node, because each page links to its own course page.
module PrerequisiteTreeHelper
  def prerequisite_tree_html(tree, &course_link)
    PrerequisiteTree.new(tree).fold do |node, parts, depth|
      case node["type"]
      when "and", "or"
        joined = safe_join(parts, tag.span(" #{node['type']} ", class: "text-on-surface-variant uppercase text-xs font-medium"))
        depth.positive? ? safe_join([ "(", joined, ")" ]) : joined
      when "course"
        min_grade = tag.span(" (min #{node['min_grade']})", class: "text-xs text-on-surface-variant") if node["min_grade"].present?
        safe_join([ capture(node, &course_link), min_grade ].compact)
      when "test"
        tag.span([ node["name"], node["score"].presence ].compact.join(" "))
      end
    end
  end
end
