# frozen_string_literal: true

require "digest"

module AcademicProfiles
  # Stores the academic profile the extension sends from the LeopardWeb
  # Student Profile page, or from its settings when the student changes a
  # value (PUT /api/user/academic_profile).
  #
  # The programs in the payload are the full list. A program that matches an
  # active row keeps that row. An active row that is not in the list ends, and
  # is never deleted, so a change of major keeps the old major.
  #
  # A LeopardWeb payload that is the same as the last LeopardWeb payload
  # changes nothing. Without this, each course sync would undo a value the
  # student changed in the settings.
  class Sync < ApplicationService
    SOURCES = StudentProgram::SOURCES.values.freeze
    MAX_PROGRAMS = 10
    MAX_LENGTH = 200

    PROFILE_FIELDS = %i[level class_standing admit_type].freeze
    PROGRAM_FIELDS = %i[code name degree college department concentration study_path].freeze
    # The fields that name a program. A change in another field updates the
    # row in place.
    IDENTITY_FIELDS = %i[role code name concentration study_path catalog_term_uid].freeze

    attr_reader :user, :payload

    def initialize(user, payload)
      @user = user
      @payload = payload.to_h.with_indifferent_access
      super()
    end

    # Returns the user's AcademicProfile. Raises InvalidProfileError.
    def call
      source = payload[:source].to_s
      raise InvalidProfileError, "source must be one of: #{SOURCES.join(', ')}" unless SOURCES.include?(source)

      profile_attributes = normalize_profile
      programs = normalize_programs
      digest = Digest::SHA256.hexdigest([ profile_attributes, programs ].to_json)

      # user_id, not user: with user, a create that loses the race sets the
      # unsaved record on user.academic_profile.
      profile = AcademicProfile.create_or_find_by!(user_id: user.id)

      AcademicProfile.transaction do
        profile.lock!
        next if source == "leopardweb" && profile.leopardweb_digest == digest

        profile.assign_attributes(profile_attributes)
        profile.assign_attributes(leopardweb_digest: digest, leopardweb_synced_at: Time.current) if source == "leopardweb"
        profile.save!

        sync_programs(programs, source)
      end

      profile
    end

    private

    def normalize_profile
      PROFILE_FIELDS.index_with { |field| text(payload[field], field) }
                    .merge(admit_term_uid: term_uid(payload[:admit_term], "admit_term"))
    end

    def normalize_programs
      programs = payload[:programs]
      raise InvalidProfileError, "programs must be a list" unless programs.is_a?(Array)
      raise InvalidProfileError, "programs can have at most #{MAX_PROGRAMS} entries" if programs.size > MAX_PROGRAMS

      programs.each_with_index.map do |program, index|
        raise InvalidProfileError, "programs[#{index}] must be an object" unless program.is_a?(Hash)

        program = program.with_indifferent_access
        role = program[:role].to_s
        unless StudentProgram::ROLES.value?(role)
          raise InvalidProfileError, "programs[#{index}].role must be one of: #{StudentProgram::ROLES.values.join(', ')}"
        end

        attributes = PROGRAM_FIELDS.index_with { |field| text(program[field], "programs[#{index}].#{field}") }
        raise InvalidProfileError, "programs[#{index}].name is required" if attributes[:name].nil?

        attributes.merge(role: role, catalog_term_uid: term_uid(program[:catalog_term], "programs[#{index}].catalog_term"))
      end
    end

    def sync_programs(programs, source)
      active = user.student_programs.active.to_a
      kept = []

      programs.each do |attributes|
        row = active.find { |candidate| kept.exclude?(candidate) && same_program?(candidate, attributes) }

        if row
          row.update!(attributes.merge(source: source))
          kept << row
        else
          user.student_programs.create!(attributes.merge(source: source))
        end
      end

      (active - kept).each { |row| row.update!(status: :ended, ended_at: Time.current) }
    end

    def same_program?(row, attributes)
      IDENTITY_FIELDS.all? { |field| comparable(row.public_send(field)) == comparable(attributes[field]) }
    end

    def comparable(value) = value.is_a?(String) ? value.downcase : value

    def text(value, field)
      return nil if value.nil?
      raise InvalidProfileError, "#{field} must be a string" unless value.is_a?(String)

      value = value.squish
      raise InvalidProfileError, "#{field} can have at most #{MAX_LENGTH} characters" if value.length > MAX_LENGTH

      value.presence
    end

    def term_uid(value, field)
      return nil if value.blank?

      TermCode.parse(value) ||
        raise(InvalidProfileError.new("#{field} must be a term such as \"Fall 2025\"", code: "invalid_term"))
    end
  end
end
