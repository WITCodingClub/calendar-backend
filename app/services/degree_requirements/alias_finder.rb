# frozen_string_literal: true

module DegreeRequirements
  # Finds the old and new code of each course that Wentworth renumbered in
  # 2015-2016 (COMP128 to COMP1000), and saves the pairs as CourseCodeAlias
  # rows for a person to check (#865). No catalog lists the old and new
  # numbers, so the pairs come from matches:
  #
  # - title_match: the same subject and title in the 2014-2015 catalog (3
  #   digits) and the 2015-2016 catalog (4 digits). The titles are the
  #   CatalogYearCourse rows that the PDF import writes from the plans.
  # - banner: a Banner term with sections of both codes, with the same
  #   subject and title. Fall 2015 and later still list some 3-digit codes.
  #
  # A title must name one course on each side, so "Special Topics" makes no
  # pair. A pair that is already saved, in either direction, is left as it
  # is, also when a person removed its review. It only adds rows.
  class AliasFinder
    Result = Data.define(:added, :title_match, :banner)

    OLD_YEAR = 2014
    NEW_YEAR = 2015

    def self.call = new.call

    def call
      pairs = catalog_pairs.map { |pair| pair.merge(source: "title_match") } +
              banner_pairs.map { |pair| pair.merge(source: "banner") }
      added = Hash.new(0)
      pairs.uniq { |pair| pair.values_at(:from, :to) }.each do |pair|
        added[pair[:source]] += 1 if save(pair)
      end
      Result.new(added: added.values.sum, title_match: added["title_match"], banner: added["banner"])
    end

    # "Intro to Computer Science &amp; Networking" and "Introduction to
    # Computer Science and Networking" are the same title.
    def self.title_key(title)
      CGI.unescapeHTML(title.to_s).downcase.gsub("&", " and ").gsub(/\bintro\b\.?/, "introduction")
         .gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
    end

    private

    def catalog_pairs
      old_year = CatalogYear.find_by(start_year: OLD_YEAR)
      new_year = CatalogYear.find_by(start_year: NEW_YEAR)
      return [] if old_year.nil? || new_year.nil?

      old = CatalogYearCourse.where(catalog_year: old_year, course_number: ...1000).pluck(:subject_code, :course_number, :title)
      new = CatalogYearCourse.where(catalog_year: new_year, course_number: 1000..).pluck(:subject_code, :course_number, :title)
      pairs(old, new).map { |pair| pair.merge(note: "#{old_year.name} and #{new_year.name} catalogs: #{pair[:title]}") }
    end

    def banner_pairs
      rows = Course.joins(:term).distinct.pluck("terms.uid", :subject, :course_number, :title)
      rows.group_by(&:first).flat_map do |uid, term_rows|
        courses = term_rows.map { |_, subject, number, title| [ subject, number, title ] }
        old, new = courses.partition { |_, number, _| number < 1000 }
        pairs(old, new).map { |pair| pair.merge(note: "Banner term #{uid}: #{pair[:title]}") }
      end
    end

    # [{ from:, to:, title: }] for each subject and title that names exactly
    # one old code and one new code.
    def pairs(old, new)
      old_by_key = old.group_by { |subject, _, title| [ subject, self.class.title_key(title) ] }
      new_by_key = new.group_by { |subject, _, title| [ subject, self.class.title_key(title) ] }
      old_by_key.filter_map do |key, old_rows|
        new_rows = new_by_key[key]
        next if key.last.blank? || new_rows.nil?

        old_codes = old_rows.map { |subject, number, _| [ subject, number ] }.uniq
        new_codes = new_rows.map { |subject, number, _| [ subject, number ] }.uniq
        next unless old_codes.one? && new_codes.one?

        { from: old_codes.first, to: new_codes.first, title: CGI.unescapeHTML(old_rows.first.last.to_s) }
      end
    end

    def save(pair)
      (from_subject, from_number), (to_subject, to_number) = pair.values_at(:from, :to)
      exists = CourseCodeAlias.where(from_subject_code: from_subject, from_course_number: from_number,
                                     to_subject_code: to_subject, to_course_number: to_number)
                              .or(CourseCodeAlias.where(from_subject_code: to_subject, from_course_number: to_number,
                                                        to_subject_code: from_subject, to_course_number: from_number))
                              .exists?
      return false if exists

      CourseCodeAlias.create!(from_subject_code: from_subject, from_course_number: from_number, to_subject_code: to_subject,
                              to_course_number: to_number, source: pair[:source], note: pair[:note].truncate(255))
      true
    end
  end
end
