# frozen_string_literal: true

module AcademicProfiles
  # A student's correction of a value that LeopardWeb sent (#867), from the
  # My programs dashboard page. It sends the stored profile and the active
  # programs to Sync with source "student", with the student's changes, so
  # the dashboard and the extension settings use the same write path.
  #
  # Sync matches each program to an active row. A change to a field that
  # names a program (role, code, name, concentration, study path, or catalog
  # term) ends the old row and creates a new one, as a change of major does.
  # A change to another field updates the row in place.
  class StudentCorrection
    PROFILE_FIELDS = %i[level class_standing admit_type admit_term].freeze
    PROGRAM_FIELDS = %i[role code name degree college department concentration study_path catalog_term].freeze

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # Changes the profile fields. Raises InvalidProfileError.
    def profile!(changes)
      locked do |profile|
        sync(profile_payload(profile).merge(changes.to_h.symbolize_keys.slice(*PROFILE_FIELDS)), programs_payload)
      end
    end

    # Changes the fields of one active program. Raises InvalidProfileError.
    def program!(program, changes)
      changes = changes.to_h.symbolize_keys.slice(*PROGRAM_FIELDS)

      locked do |profile|
        unless program.user_id == user.id && active_programs.any? { |row| row.id == program.id }
          raise InvalidProfileError, "Only an active program can be corrected"
        end

        programs = active_programs.map do |row|
          attributes = program_attributes(row)
          row.id == program.id ? attributes.merge(changes) : attributes
        end
        sync(profile_payload(profile), programs)
      end
    end

    private

    # Reads the stored values and syncs under the lock that Sync takes, so a
    # LeopardWeb sync at the same time cannot change them in between. Sync
    # takes the same row lock again in the same transaction.
    def locked
      profile = AcademicProfile.create_or_find_by!(user_id: user.id)
      profile.with_lock { yield profile }
    end

    def sync(profile, programs)
      Sync.new(user, profile.merge(source: "student", programs: programs)).call
    end

    def profile_payload(profile)
      {
        level:          profile.level,
        class_standing: profile.class_standing,
        admit_type:     profile.admit_type,
        admit_term:     TermCode.label(profile.admit_term_uid)
      }
    end

    def programs_payload = active_programs.map { |row| program_attributes(row) }

    def active_programs
      @active_programs ||= user.student_programs.active.order(:id).to_a
    end

    def program_attributes(row)
      {
        role:          row.role,
        code:          row.code,
        name:          row.name,
        degree:        row.degree,
        college:       row.college,
        department:    row.department,
        concentration: row.concentration,
        study_path:    row.study_path,
        catalog_term:  row.catalog_term
      }
    end
  end
end
