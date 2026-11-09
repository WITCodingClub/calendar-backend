# frozen_string_literal: true

module Catalog
  # Course.subject holds Banner's subject label with the code at the end:
  # "Computer Science (COMP)". Every lookup by code reads the code from there
  # (Course.prefix_of), and Catalog::SectionQuery matches "%(COMP)".
  #
  # Banner's label for most subjects already ends with the code. Some labels do
  # not: "Climate Resilience" is CRES, "Building Construction" is BLDG, and
  # "Graduate Internship (optional)" is INTN. One label ends with a different
  # code: "Facilities Management (CPCE)" is CPFM. getClassDetails gives only
  # the label, so the code comes from Banner's subject list for the term.
  module SubjectLabels
    CACHE_TTL = 1.day
    BARE_CODE = /\A[A-Z0-9]{2,6}\z/

    # The label with the code at the end. A different code at the end of the
    # label is replaced: "Facilities Management (CPCE)" with CPFM gives
    # "Facilities Management (CPFM)".
    def self.label(description, code)
      description = description.to_s.strip
      code = code.to_s.strip.upcase
      return description if code.empty?
      return code if description.empty?

      "#{name(description)} (#{code})"
    end

    # The label for a subject as getClassDetails gives it. A bare code
    # ("COMP") is kept. stored is the section's current label: when it has a
    # code and the same name, Banner is not asked again. When Banner's subject
    # list does not have the label, it is kept as it is.
    def self.for_term(description, term_uid, stored: nil)
      description = description.to_s.strip
      return description if description.empty? || description.match?(BARE_CODE)
      return stored if stored.present? && code_suffix?(stored) && name(stored) == name(description)

      code = codes(term_uid)[description]
      code ? label(description, code) : description
    end

    # The label without a code at the end: "Computer Science".
    def self.name(label)
      label.to_s.sub(Course::SUBJECT_CODE_SUFFIX, "").strip
    end

    # description => code for one term, from Banner's subject list. A failed
    # request is reported and not kept, so the next call asks again.
    def self.codes(term_uid)
      cache_key = "catalog/subject_codes/#{term_uid}"
      cached = Rails.cache.read(cache_key)
      return cached if cached

      codes = LeopardWebClient.get_subjects(term: term_uid).to_h { |s| [ s[:description].to_s.strip, s[:code].to_s.strip.upcase ] }
      Rails.cache.write(cache_key, codes, expires_in: CACHE_TTL) if codes.any?
      codes
    rescue BannerThrottle::CooldownError
      raise
    rescue => e
      Rails.error.report(e, handled: true, context: { term_uid: term_uid })
      {}
    end

    # "Computer Science (COMP)" ends with a code. "Graduate Internship
    # (optional)" does not: a code is upper case.
    def self.code_suffix?(label)
      label.match?(Course::SUBJECT_CODE_SUFFIX)
    end
  end
end
