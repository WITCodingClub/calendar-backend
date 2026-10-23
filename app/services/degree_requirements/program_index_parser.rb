# frozen_string_literal: true

module DegreeRequirements
  # Reads the program index (/programs-az/) of one catalog year. Since
  # 2020-2021 the index is a tree of school, department, and program; in
  # 2019-2020 it is a flat A-Z list. A link with no list under it is a
  # program in both shapes. A department link has its programs under it.
  class ProgramIndexParser
    require "nokogiri"

    Entry = Data.define(:name, :path, :slug, :kind, :level, :parent_name)

    CONTAINERS = "#textcontainer, #minorstextcontainer"

    # The first rule that matches the program name gives its kind. Order
    # matters: "Exploratory Track in Engineering" is not a concentration, and
    # "Data Analytics Certificate (graduate)" is not a master's degree.
    KIND_RULES = [
      [ "exploratory",   /\Aexploratory/i ],
      [ "concentration", /concentration|track\z/i ],
      [ "certificate",   /certificate/i ],
      [ "minor",         /\bminor\b/i ],
      [ "associate",     /associate|\bA\.?\s?A\.?\s?S\b/i ],
      [ "master",        /master|\bM\.\s?(?:S|Eng|Arch)\b|\bMBA\b/i ],
      [ "bachelor",      /bachelor|\bB\.?\s?S\b/i ]
    ].freeze

    # "Building Sciences, B.S. - Construction Management Concentration" and
    # "Engineering B.S.- Mechanical Engineering Concentration" name the major
    # before the dash.
    PARENT_SPLIT = /\s+-\s*|(?<=\.)-\s+/

    def initialize(html, home_path:)
      @doc = Nokogiri::HTML(html)
      @home_path = home_path
    end

    # The programs, once each, in page order. A name that matches no kind is
    # left out, and listed in #unclassified.
    def entries
      @entries ||= begin
        @unclassified = []
        program_links.filter_map { |name, path| build_entry(name, path) }
      end
    end

    def unclassified
      entries
      @unclassified
    end

    def self.kind_for(name)
      KIND_RULES.find { |_, pattern| name.match?(pattern) }&.first
    end

    def self.level_for(name, kind)
      return "graduate" if kind == "master"
      return "graduate" if kind == "certificate" && name.match?(/graduate/i)

      "undergraduate"
    end

    private

    def program_links
      seen = {}
      @doc.css(CONTAINERS).each do |container|
        container.css("li").each do |li|
          link = li.at_css("> a[href]")
          next if link.nil? || li.at_css("ul")

          path = program_path(link["href"])
          next if path.nil? || seen.key?(path)

          seen[path] = link.text.gsub(/[[:space:]]+/, " ").strip
        end
      end
      seen.map { |path, name| [ name, path ] }
    end

    # The site path of a program page, or nil for a link that is not one: a
    # PDF, another site, or a page above the department level.
    def program_path(href)
      return nil unless href.start_with?("/") && !href.include?(".pdf")

      relative = href.split("#").first.delete_prefix(@home_path.chomp("/"))
      segments = relative.split("/").compact_blank
      return nil if segments.size < 2 || segments.first == "programs-az"

      "#{@home_path}#{segments.join('/')}/"
    end

    def build_entry(name, path)
      kind = self.class.kind_for(name)
      if kind.nil?
        @unclassified << name
        return nil
      end

      parent_name = kind == "concentration" && name.match?(PARENT_SPLIT) ? name.split(PARENT_SPLIT, 2).first.strip : nil
      Entry.new(name: name, path: path, slug: path.split("/").compact_blank.last, kind: kind,
                level: self.class.level_for(name, kind), parent_name: parent_name)
    end
  end
end
