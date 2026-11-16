# frozen_string_literal: true

module AcademicProfiles
  # A student's correction of a profile value that LeopardWeb sent (#867),
  # from the My programs dashboard page. It sends the stored profile to Sync
  # with source "student", with the student's changes, so the dashboard and
  # the extension settings use the same write path.
  #
  # The programs come only from LeopardWeb, so a student cannot correct them.
  class StudentCorrection
    PROFILE_FIELDS = %i[level class_standing admit_type admit_term].freeze

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # Changes the profile fields. Raises InvalidProfileError.
    def profile!(changes)
      locked do |profile|
        sync(profile_payload(profile).merge(changes.to_h.symbolize_keys.slice(*PROFILE_FIELDS)))
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

    def sync(profile)
      Sync.new(user, profile.merge(source: "student", programs: [])).call
    end

    def profile_payload(profile)
      {
        level:          profile.level,
        class_standing: profile.class_standing,
        admit_type:     profile.admit_type,
        admit_term:     TermCode.label(profile.admit_term_uid)
      }
    end
  end
end
