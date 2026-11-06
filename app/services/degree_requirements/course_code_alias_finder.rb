# frozen_string_literal: true

module DegreeRequirements
  # Finds the course code aliases of the renumbering in 2015-2016, when most
  # 3-digit codes got 4 digits (COMP128 became COMP1000). No catalog lists
  # the old and new codes, so the aliases come from matches:
  #
  # - catalog: the same subject and title in the 2014-2015 catalog (old code)
  #   and the 2015-2016 catalog (new code), from the plans of study and the
  #   course tables in the PDFs.
  # - banner: the same subject and title on a 3-digit and a 4-digit code in
  #   the Banner sections of any term.
  #
  # A title matches only when one old code and one new code of the subject
  # have it. When the two sources give different codes for one course, the
  # course gets no alias. Every new alias waits for a person in the review
  # queue (/admin/course_code_alias_reviews). A stored alias is never changed.
  class CourseCodeAliasFinder
    Result = Data.define(:created, :catalog, :banner, :existing, :conflicts)
    Pair = Data.define(:subject_code, :from_number, :to_number, :source, :note, :placed)

    OLD_YEAR = 2014
    NEW_YEAR = 2015
    # "COMP128         Computer Science I                    4" in a course table.
    TABLE_ROW = /(?:\A|\s{2,})([A-Z]{2,5})(\d{3,4})\s{2,}([A-Z][A-Za-z0-9&,'\/\-: ]{2,80}?)\s{2,}\d{1,2}\s*\z/

    # texts: the pdftotext text of the 2014-2015 and 2015-2016 catalogs, by
    # start year. A missing text skips the catalog matches.
    def initialize(texts:)
      @texts = texts
    end

    def call
      catalog = catalog_pairs
      banner = banner_pairs
      pairs, conflicts = merge(catalog, banner)
      # The catalogs and Banner can each pair a different old code with one
      # new code. Then one of them is wrong, and neither is kept.
      sources = pairs.group_by { |pair| [ pair.subject_code, pair.to_number ] }.transform_values { |group| group.map(&:from_number).uniq }
      shared, pairs = pairs.partition { |pair| sources[[ pair.subject_code, pair.to_number ]].size > 1 }
      counts = Hash.new(0)
      counts[:conflicts] = conflicts + shared.map { |pair| [ pair.subject_code, pair.from_number ] }.uniq.size
      targets = pairs.group_by { |pair| [ pair.subject_code, pair.from_number ] }.transform_values { |group| group.map(&:to_number) }
      pairs.each { |pair| store(pair, counts, targets[[ pair.subject_code, pair.from_number ]]) }
      Result.new(**Result.members.index_with { |key| counts[key] })
    end

    private

    def catalog_pairs
      old_text = @texts[OLD_YEAR]
      new_text = @texts[NEW_YEAR]
      return [] if old_text.blank? || new_text.blank?

      old_titles, old_slots = catalog_titles(old_text, OLD_YEAR)
      new_titles, new_slots = catalog_titles(new_text, NEW_YEAR)
      # "Computer Science I" is COMP1000 and COMP1070 in 2015-2016. COMP1000
      # sits where COMP128 sat in the Computer Science plan, so it wins.
      same_slot = ->(from, candidates) { candidates.select { |to| old_slots[from].intersect?(new_slots[to]) } }
      match(old_titles, new_titles, "title_match", tie_break: same_slot) do |title|
        "Same title in the #{OLD_YEAR}-#{OLD_YEAR + 1} and #{NEW_YEAR}-#{NEW_YEAR + 1} catalogs: #{title}"
      end
    end

    # The titles of each code, { ["COMP", 128] => Set["computer science i"] },
    # and the plan places of each code, { ["COMP", 128] => Set[["computer
    # science", 1, "fall"]] }.
    def catalog_titles(text, start_year)
      titles = Hash.new { |hash, key| hash[key] = Set.new }
      slots = Hash.new { |hash, key| hash[key] = Set.new }
      PdfCatalog.parser_for(start_year).call(text).plans.each do |plan|
        program = normalize(plan.heading.gsub(/\([^)]*\)/, ""))
        plan.items.each do |item|
          next unless item.kind == "course"

          code = [ item.subject_code, item.course_number ]
          titles[code] << normalize(item.title) if item.title.present?
          slots[code] << [ program, item.year_index, item.season ]
        end
      end
      text.each_line do |line|
        next unless (row = line.chomp.match(TABLE_ROW))

        titles[[ row[1], row[2].to_i ]] << normalize(row[3])
      end
      [ titles, slots ]
    end

    def banner_pairs
      titles = Hash.new { |hash, key| hash[key] = Set.new }
      terms = Hash.new { |hash, key| hash[key] = [] }
      Course.joins(:term).distinct.pluck(:subject, :course_number, :title, "terms.uid").each do |subject, number, title, uid|
        code = [ subject.to_s[/\(([^)]+)\)\s*\z/, 1] || subject.to_s.strip, number ]
        titles[code] << normalize(title)
        terms[code] << uid
      end

      match(titles, titles, "banner") do |title, from, to|
        "Same title in Banner: #{title}. #{from.join} in #{terms[from].minmax.uniq.join('-')}, " \
          "#{to.join} in #{terms[to].minmax.uniq.join('-')}"
      end
    end

    # Pairs each old code with the new code of the same subject and title,
    # when the title belongs to one old code and one new code. When the title
    # belongs to several new codes, tie_break keeps the ones that took the
    # old code's place in a plan. Each of those is an alias: the course was
    # split, as COMP128 became COMP1000 for Computer Science and COMP1070
    # for Applied Mathematics.
    #
    # A plain title match that gives a code two partners is left out: then
    # one of its titles points to the wrong course.
    def match(old_titles, new_titles, source, tie_break: nil)
      old_index = index_by_title(old_titles.select { |(_, number), _| number < 1000 })
      new_index = index_by_title(new_titles.select { |(_, number), _| number >= 1000 })
      pairs = old_index.flat_map do |(subject, title), old_codes|
        new_codes = new_index[[ subject, title ]]
        next [] unless old_codes.one? && new_codes

        placed = new_codes.size > 1 && !tie_break.nil?
        new_codes = tie_break.call(old_codes.first, new_codes) if placed
        next [] unless placed ? new_codes.any? : new_codes.one?

        from = old_codes.first
        new_codes.map do |to|
          Pair.new(subject_code: subject, from_number: from.last, to_number: to.last, source: source,
                   note: yield(title, from, to), placed: placed)
        end
      end
      one_to_one(pairs)
    end

    def one_to_one(pairs)
      placed, plain = pairs.partition(&:placed)
      placed_from = placed.to_set { |pair| [ pair.subject_code, pair.from_number ] }
      plain = plain.reject { |pair| placed_from.include?([ pair.subject_code, pair.from_number ]) }
      targets = plain.group_by { |pair| [ pair.subject_code, pair.from_number ] }.transform_values { |group| group.map(&:to_number).uniq }
      sources = plain.group_by { |pair| [ pair.subject_code, pair.to_number ] }.transform_values { |group| group.map(&:from_number).uniq }
      plain = plain.select do |pair|
        targets[[ pair.subject_code, pair.from_number ]].one? && sources[[ pair.subject_code, pair.to_number ]].one?
      end
      (placed + plain).uniq { |pair| [ pair.subject_code, pair.from_number, pair.to_number ] }
    end

    # { ["COMP", "computer science i"] => [["COMP", 128]], ... }. A title
    # too short or too common to name one course is left out.
    def index_by_title(titles)
      index = Hash.new { |hash, key| hash[key] = [] }
      titles.each do |code, names|
        names.each do |name|
          next if name.length < 4 || name.match?(/\A(?:special topics|independent study|co ?op|directed study)/)

          index[[ code.first, name ]] << code
        end
      end
      index.transform_values(&:uniq)
    end

    # The catalog and Banner pairs of each old code. When one source gives
    # new codes that the other does not, and neither list holds the other,
    # the sources disagree, and the old code gets no alias.
    def merge(catalog, banner)
      conflicts = 0
      keys = (catalog + banner).map { |pair| [ pair.subject_code, pair.from_number ] }.uniq
      kept = keys.flat_map do |key|
        from_catalog = catalog.select { |pair| [ pair.subject_code, pair.from_number ] == key }
        from_banner = banner.select { |pair| [ pair.subject_code, pair.from_number ] == key }
        a = from_catalog.to_set(&:to_number)
        b = from_banner.to_set(&:to_number)
        if a.any? && b.any? && !(a <= b || b <= a)
          conflicts += 1
          next []
        end

        (from_catalog + from_banner).group_by(&:to_number).values.map do |group|
          group.first.with(note: group.map(&:note).join("\n"))
        end
      end
      [ kept, conflicts ]
    end

    # targets: the new codes that this run finds for the old code. A stored
    # alias to another code means a person or an earlier run knows better,
    # so the old code gets no new alias.
    def store(pair, counts, targets)
      existing = CourseCodeAlias.where(from_subject_code: pair.subject_code, from_course_number: pair.from_number)
      if existing.exists?(to_subject_code: pair.subject_code, to_course_number: pair.to_number)
        counts[:existing] += 1
        return
      end
      other_old = CourseCodeAlias.where(to_subject_code: pair.subject_code, to_course_number: pair.to_number)
                                 .where.not(from_subject_code: pair.subject_code, from_course_number: pair.from_number)
      if existing.where.not(to_subject_code: pair.subject_code, to_course_number: targets).exists? || other_old.exists?
        counts[:conflicts] += 1
        return
      end

      created = CourseCodeAlias.create(from_subject_code: pair.subject_code, from_course_number: pair.from_number,
                                       to_subject_code: pair.subject_code, to_course_number: pair.to_number,
                                       source: pair.source, note: pair.note.truncate(255))
      if created.persisted?
        counts[:created] += 1
        counts[pair.source == "banner" ? :banner : :catalog] += 1
      else
        counts[:conflicts] += 1
        Rails.logger.info("[DegreeRequirements::CourseCodeAliasFinder] #{created.from_code}: #{created.errors.full_messages.to_sentence}")
      end
    end

    # "Data Structures & Algorithms" and "Data Structures and Algorithms" are
    # one title. Banner writes some titles with "&amp;".
    def normalize(title)
      title.to_s.downcase.gsub("&amp;", "&").gsub("&", " and ").gsub(/[^a-z0-9]+/, " ").squish
    end
  end
end
