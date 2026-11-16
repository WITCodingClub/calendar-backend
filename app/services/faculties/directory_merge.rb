# frozen_string_literal: true

module Faculties
  # Writes one card of the faculty directory (Faculties::Directory) onto a
  # Faculty row. The full sync and the lookup of one person use the same rules:
  # a longer name wins, a field that the directory changes is updated, and a
  # field that only the directory knows is filled once.
  class DirectoryMerge
    # A title with one of these words is a teaching title.
    FACULTY_TITLE_WORDS = %w[professor instructor lecturer dean chair faculty adjunct].freeze

    # First, middle, and last name from "First Middle Last". One word is both
    # the first and the last name.
    def self.name_parts(display_name)
      parts = display_name.to_s.strip.split(/\s+/)
      case parts.length
      when 0 then {}
      when 1 then { first_name: parts[0], last_name: parts[0] }
      when 2 then { first_name: parts[0], last_name: parts[1] }
      else { first_name: parts[0], middle_name: parts[1..-2].join(" "), last_name: parts[-1] }
      end
    end

    # Saves the card onto the faculty row. Returns the names of the changed
    # columns, empty when nothing changed. A new photo URL also downloads the
    # photo.
    def self.apply(faculty, card)
      new(faculty, card).apply
    end

    def initialize(faculty, card)
      @faculty = faculty
      @card    = card
      @name    = self.class.name_parts(card[:display_name])
    end

    def apply
      @faculty.assign_attributes(attributes)
      return [] unless @faculty.changed?

      @faculty.save!
      # The photo download writes a column too, so read the changes first.
      changed = @faculty.saved_changes.keys
      @faculty.update_photo_from_url!(@faculty.photo_url) if @faculty.saved_change_to_photo_url? && @faculty.photo_url.present?
      changed
    end

    private

    def attributes
      attrs = { directory_raw_data: raw_data, directory_last_synced_at: Time.current }
      attrs[:first_name]      = @name[:first_name]   if longer?(@name[:first_name], @faculty.first_name)
      attrs[:last_name]       = @name[:last_name]    if longer?(@name[:last_name], @faculty.last_name)
      attrs[:middle_name]     = @name[:middle_name]  if @name[:middle_name].present? && @faculty.middle_name.blank?
      attrs[:display_name]    = @card[:display_name] if longer?(@card[:display_name], @faculty.display_name)
      attrs[:title]           = @card[:title]        if @card[:title].present? && @faculty.title != @card[:title]
      attrs[:phone]           = @card[:phone]        if @card[:phone].present? && @faculty.phone != @card[:phone]
      attrs[:office_location] = @card[:office_location] if @card[:office_location].present? && @faculty.office_location.blank?
      attrs[:department]      = @card[:department]   if @card[:department].present? && @faculty.department.blank?
      attrs[:school]          = @card[:school]       if @card[:school].present? && @faculty.school.blank?
      attrs[:photo_url]       = @card[:photo_url]    if @card[:photo_url].present? && @faculty.photo_url != @card[:photo_url]
      attrs[:employee_type]   = employee_type        if @faculty.employee_type.blank?
      attrs
    end

    def longer?(value, current)
      value.present? && (current.blank? || value.length > current.to_s.length)
    end

    def employee_type
      title = @card[:title].to_s.downcase
      FACULTY_TITLE_WORDS.any? { |word| title.include?(word) } ? "faculty" : "staff"
    end

    def raw_data
      {
        fetched_at:  Time.current.iso8601,
        raw_html:    @card[:raw_html],
        profile_url: @card[:profile_url],
        source_url:  Faculties::Directory::BASE_URL
      }
    end
  end
end
