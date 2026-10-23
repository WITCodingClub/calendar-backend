# frozen_string_literal: true

module DegreeRequirements
  # Reads one program page of the catalog (CourseLeaf). The required courses
  # are in the plans of study (table.sc_plangrid). The elective lists are
  # table.sc_courselist, and the minimum ("select four") is only in the
  # heading above a list. docs/degree-requirements.md shows the row shapes.
  class ProgramPageParser
    require "nokogiri"

    Page = Data.define(:name, :start_year, :school_name, :department_name, :description,
                       :total_credits, :plans, :groups, :digest)
    Plan = Data.define(:name, :years, :accelerated, :total_credits, :items)
    # plan_index is the plan the list is printed under, or nil for a list that
    # belongs to the whole program.
    Group = Data.define(:name, :heading, :min_courses, :min_credits, :notes, :plan_index, :courses)
    GroupCourse = Data.define(:subject_code, :course_number, :requires_approval)
    # group_index points into Page#groups, for a placeholder that names a list.
    Item = Data.define(:year_index, :season, :kind, :subject_code, :course_number, :label,
                       :min_credits, :max_credits, :footnote, :options, :group_index)

    CODE = /\A\s*([A-Z]{2,5})\s*(\d{3,4})\s*\z/
    NUMBER_WORDS = %w[zero one two three four five six seven eight nine ten eleven twelve].freeze
    SEASONS = [ [ "fall", /fall|semester one|first semester/i ],
                [ "spring", /spring|semester two|second semester/i ],
                [ "summer", /summer|semester three|third semester/i ] ].freeze
    MINIMUM = /(?:select|choose|take|complete)\s+(?:any\s+|at least\s+|a minimum of\s+|the following\s+)?(\w+)\s*(?:\((\d+)\))?\s*(credits?|courses?|classes|electives?)?/i
    CREDIT_TOTAL = /(\d+)\s+(?:semester\s+)?credit(?:s|\s+hours)?\b/i
    # A note in a list that starts a new part of it, such as "Select one (1)
    # course from the following courses:" or "and complete the following two courses:".
    LIST_START = /\A(?:and\s+)?(?:select|choose|take|complete)\b|following/i
    NAME_LIMIT = 80
    DESCRIPTION_LIMIT = 5_000
    # Part of the digest. Raise it when a change to this parser should write
    # every page again, also the pages that did not change.
    VERSION = 1

    def initialize(html)
      @doc = Nokogiri::HTML(html)
      @content = @doc.at_css("article#content") || @doc.at_css("body") || @doc
      @html = html
    end

    def call
      plans = []
      groups = []
      heading = nil

      @content.css("h2, h3, h4, table.sc_plangrid, table.sc_courselist").each do |node|
        if node.name == "table"
          # A heading names the table only from the same tab. The last
          # heading of the overview tab says nothing about the plan.
          title = heading&.first if heading&.last == tab_of(node)
          if node["class"].to_s.include?("sc_plangrid")
            plans << parse_plan(node, title || "Plan of Study")
          else
            groups.concat(parse_course_list(node, title, plans.size - 1))
          end
          heading = nil
        elsif (text = spaced_text(node).presence)
          heading = [ text, tab_of(node) ]
        end
      end

      groups = assign_groups_to_plans(groups, plans.size)
      plans = link_placeholders(plans, groups)

      Page.new(name: squish((@doc.at_css("h1.page-title") || @doc.at_css("h1"))&.text), start_year: CatalogSource.page_start_year(@html),
               school_name: breadcrumb[0], department_name: breadcrumb[1], description: description,
               total_credits: total_credits(plans), plans: plans, groups: groups,
               digest: Digest::SHA256.hexdigest("#{VERSION}:#{@content.to_html}"))
    end

    private

    # The breadcrumb is Catalog Home // school // department // program. A
    # program directly under a school has no department.
    def breadcrumb
      @breadcrumb ||= begin
        crumbs = @doc.css("#breadcrumb li").map { |li| squish(li.text.delete_suffix("//")).delete_suffix("//").strip }
        middle = crumbs[1...-1] || []
        [ middle[0].presence, middle[1].presence ]
      end
    end

    def description
      node = @doc.at_css("#programoverviewtextcontainer")
      squish(node&.text).presence&.truncate(DESCRIPTION_LIMIT)
    end

    def total_credits(plans)
      text = squish(@content.text)
      text[/total credits(?: for (?:the )?degree| required)?:?\s*(\d+)/i, 1]&.to_i || plans.first&.total_credits
    end

    # -- Plans of study ------------------------------------------------------

    def parse_plan(table, name)
      items = []
      year_index = 0
      season = nil
      total = nil

      table.css("tr").each do |row|
        classes = row["class"].to_s.split
        if classes.include?("plangridyear")
          year_index += 1
        elsif classes.include?("plangridterm")
          year_index = 1 if year_index.zero?
          season = season_for(row.at_css("th")&.text) || season
        elsif classes.include?("plangridtotal")
          total = credits_of(row.css("td").last&.text)&.first
        elsif !classes.include?("plangridsum")
          parse_plan_row(row, items, [ year_index, 1 ].max, season || "fall")
        end
      end

      Plan.new(name: name, years: [ year_index, 1 ].max, accelerated: name.match?(/three[\s-]year|3[\s-]year|accelerated/i),
               total_credits: total, items: items)
    end

    def parse_plan_row(row, items, year_index, season)
      code_cell = row.at_css("td.codecol")
      return if code_cell.nil?

      min, max = credits_of(row.at_css("td.hourscol")&.text)
      indented = code_cell.element_children.first&.[]("class").to_s.include?("blockindent")
      footnote = row.css("sup").map { |sup| squish(sup.text) }.compact_blank.join(",").presence
      base = { year_index: year_index, season: season, group_index: nil, subject_code: nil, course_number: nil, options: [] }

      if (comment = code_cell.at_css("span.comment"))
        # An indented note with no credits, such as "PHYS1250 will also
        # satisfy the PHYS requirement", explains the row above it.
        return if indented && min.nil?

        label = label_text(comment)
        # "HSS Elective*" points to a note under the plan.
        footnote = [ footnote, "*" ].compact.join(",") if label.end_with?("*")
        items << Item.new(**base, footnote: footnote, kind: "placeholder", label: label.delete_suffix("*").strip,
                                  min_credits: min, max_credits: max)
        return
      end

      codes = code_cell.css("a.code").filter_map { |link| parse_code(link.text) }
      return if codes.empty?

      # Indented courses with no credits under "Select one of the following"
      # are the options of that row.
      if indented && min.nil? && (last = items.last) && last.kind.in?(%w[placeholder choice]) &&
         last.year_index == year_index && last.season == season
        options = last.options + codes.map { |subject, number| { "subject_code" => subject, "course_number" => number } }
        items[-1] = last.with(kind: options.size >= 2 ? "choice" : last.kind, options: options)
        return
      end

      title = squish(row.at_css("td.titlecol")&.text)
      if codes.size > 1 && spaced_text(code_cell).match?(/\bor\b/i)
        options = codes.map { |subject, number| { "subject_code" => subject, "course_number" => number } }
        items << Item.new(**base, footnote: footnote, kind: "choice", options: options, label: title, min_credits: min, max_credits: max)
      elsif codes.size > 1
        # "MATH1776 & MATH1777" takes both. The row's credits are for the
        # pair, so each course row has none.
        codes.each do |subject, number|
          items << Item.new(**base, footnote: footnote, kind: "course", subject_code: subject, course_number: number,
                                    label: title, min_credits: nil, max_credits: nil)
        end
      else
        subject, number = codes.first
        items << Item.new(**base, footnote: footnote, kind: "course", subject_code: subject, course_number: number,
                                  label: title, min_credits: min, max_credits: max)
      end
    end

    # -- Elective lists ------------------------------------------------------

    def parse_course_list(table, heading, plan_index)
      groups = [ new_group(heading, plan_index) ]
      approval = false
      area = nil

      table.css("tr").each do |row|
        classes = row["class"].to_s.split
        comment = row.at_css(".courselistcomment, span.comment")
        min, = credits_of(row.at_css("td.hourscol")&.text)

        if classes.include?("listsum")
          groups[-1] = groups.last.with(min_credits: min) if groups.size == 1 && groups.last.min_credits.nil?
        elsif classes.include?("areaheader")
          area = label_text(comment || row)
          groups << new_group(area, plan_index, min_credits: min)
          approval = false
        elsif comment && row.css("a.code").empty?
          text = label_text(comment)
          if text.match?(/approval/i)
            approval = true
          elsif text.match?(LIST_START)
            # "Required Courses" with "Select one (1) course" under it.
            name = [ area, text.delete_suffix(":") ].compact.join(": ")
            groups << new_group(text, plan_index, min_credits: min).with(name: name.truncate(NAME_LIMIT, separator: " "))
            approval = false
          else
            groups[-1] = groups.last.with(notes: [ groups.last.notes, text ].compact.join("\n"))
          end
        else
          row.css("a.code").filter_map { |link| parse_code(link.text) }.each do |subject, number|
            next if groups.last.courses.any? { |c| c.subject_code == subject && c.course_number == number }

            course = GroupCourse.new(subject_code: subject, course_number: number, requires_approval: approval)
            groups[-1] = groups.last.with(courses: groups.last.courses + [ course ])
          end
        end
      end

      groups.select { |group| group.courses.any? }
    end

    def new_group(text, plan_index, min_credits: nil)
      text = text.presence || "Course List"
      courses, credits = minimum(text)
      Group.new(name: group_name(text), heading: text, min_courses: courses, min_credits: min_credits || credits,
                notes: nil, plan_index: plan_index, courses: [])
    end

    # "Computer Science Electives, select four (4) courses" names the list
    # "Computer Science Electives".
    def group_name(text)
      name = text.split(/,|:|\bselect\b/i).first.to_s.strip
      (name.presence || text).truncate(NAME_LIMIT, separator: " ")
    end

    # [min_courses, min_credits] from "select four (4) courses" or "select 8 credits".
    def minimum(text)
      match = MINIMUM.match(text)
      if match.nil?
        credits = text[CREDIT_TOTAL, 1]&.to_i
        return [ nil, credits&.positive? ? credits : nil ]
      end

      count = (match[2] || match[1]).then { |word| word.match?(/\A\d+\z/) ? word.to_i : NUMBER_WORDS.index(word.downcase) }
      return [ nil, nil ] if count.nil? || count.zero?

      match[3].to_s.match?(/credit/i) ? [ nil, count ] : [ count, nil ]
    end

    # A list printed under a plan belongs to it only when the page has more
    # than one plan. With one plan, every list is for the whole program.
    def assign_groups_to_plans(groups, plan_count)
      groups.map do |group|
        group.with(plan_index: plan_count > 1 && group.plan_index >= 0 ? group.plan_index : nil)
      end
    end

    # A placeholder such as "Computer Science Elective 1" names the list
    # "Computer Science Electives" of its own plan or of the whole program.
    def link_placeholders(plans, groups)
      plans.each_with_index.map do |plan, plan_index|
        items = plan.items.map do |item|
          next item unless item.kind == "placeholder"

          key = match_key(item.label)
          index = groups.each_index.find do |i|
            group_key = match_key(groups[i].name)
            groups[i].plan_index.in?([ nil, plan_index ]) && key.present? && group_key.present? &&
              (group_key.start_with?(key) || key.start_with?(group_key))
          end
          item.with(group_index: index)
        end
        plan.with(items: items)
      end
    end

    def match_key(text)
      text.to_s.downcase.sub(/[\s\d*†]+\z/, "").gsub(/electives?/, "elective").gsub(/[^a-z]/, "")
    end

    # -- Helpers ---------------------------------------------------------------

    # The tab (overview, requirements) a node is in, or nil.
    def tab_of(node)
      node.ancestors("div").find { |div| div["id"].to_s.end_with?("textcontainer") }
    end

    def season_for(text)
      SEASONS.find { |_, pattern| text.to_s.match?(pattern) }&.first
    end

    # [min, max] from "4", "3-4", or "", as integers.
    def credits_of(text)
      numbers = text.to_s.scan(/\d+/).map(&:to_i)
      return [ nil, nil ] if numbers.empty?

      [ numbers.first, numbers.last ]
    end

    def parse_code(text)
      match = CODE.match(text.to_s.gsub(/[[:space:]]/, " "))
      match && [ match[1], match[2].to_i ]
    end

    # The text of a cell without its footnote marks.
    def label_text(node)
      copy = node.dup
      copy.css("sup").each(&:remove)
      squish(copy.text)
    end

    # The text of a node with a space between its parts, so "COMP1100<br>or"
    # does not read as "COMP1100or".
    def spaced_text(node)
      squish(node.xpath(".//text()").map(&:text).join(" "))
    end

    def squish(text)
      text.to_s.gsub(/[[:space:]]+/, " ").strip
    end
  end
end
