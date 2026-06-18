# frozen_string_literal: true

require "pg"

# Migrates user data from the legacy backend database into this app.
#
# Dependency order:
#   1. Build lookup maps (terms, courses, meeting_times) — run catalog import first
#   2. FinalExams           (manual PDF-upload data, not from catalog)
#   3. Users                (emails table → Devise user)
#   4. OauthCredentials
#   5. GoogleCalendars
#   6. Enrollments
#   7. CalendarPreferences
#   8. EventPreferences
#   9. UserExtensionConfigs (updates the one auto-created by User#after_create)
#  10. Friendships
#  11. Flipper feature flags
#  12. Blazer queries, dashboards, checks
#  13. Enrichment jobs (GoogleCalendarSync, UpdateFacultyRatings)
#
# Usage:
#   ImportFromBackendService.call(database_url: "postgresql://...", dry_run: false)
class ImportFromBackendService
  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(database_url:, dry_run: false, send_welcome_emails: false)
    @database_url = database_url
    @dry_run = dry_run
    @send_welcome_emails = send_welcome_emails

    # old_id => new_id maps, built as we go
    @user_id_map = {}
    @oauth_id_map = {}
    @gcal_id_map = {}
    @term_id_map = {}           # old backend term.id => new term.id
    @course_id_map = {}         # old backend course.id => new course.id
    @meeting_time_id_map = {}   # old backend meeting_time.id => new course_meeting_time.id

    @stats = Hash.new(0)
    @errors = []
  end

  def call
    log "=== ImportFromBackendService starting (dry_run=#{@dry_run}) ==="
    connect do |conn|
      build_term_id_map(conn)
      build_course_id_map(conn)
      build_meeting_time_id_map(conn)
      migrate_final_exams(conn)
      migrate_users(conn)
      migrate_oauth_credentials(conn)
      migrate_google_calendars(conn)
      migrate_enrollments(conn)
      migrate_calendar_preferences(conn)
      migrate_event_preferences(conn)
      migrate_user_extension_configs(conn)
      migrate_friendships(conn)
      migrate_flipper(conn)
      migrate_blazer(conn)
      queue_enrichment unless @dry_run
    end
    report
  end

  private

  # ---------------------------------------------------------------------------
  # Database connection
  # ---------------------------------------------------------------------------

  def connect
    conn = PG.connect(@database_url)
    yield conn
  ensure
    conn&.close
  end

  # ---------------------------------------------------------------------------
  # Pre-flight: build lookup maps from already-imported catalog data
  # ---------------------------------------------------------------------------

  def build_term_id_map(conn)
    log "Building term ID map..."

    rows = conn.exec("SELECT id, uid FROM terms")
    rows.each do |row|
      new_term = Term.find_by(uid: row["uid"].to_i)
      if new_term
        @term_id_map[row["id"].to_i] = new_term.id
      else
        @stats[:terms_not_found] += 1
      end
    end

    log "  Mapped #{@term_id_map.size} terms (#{@stats[:terms_not_found]} not found)"
  end

  def build_course_id_map(conn)
    log "Building course ID map..."

    # Pull every course from the backend with its CRN and the owning term's UID.
    rows = conn.exec(<<~SQL)
      SELECT c.id AS old_id, c.crn, t.uid AS term_uid
      FROM courses c
      JOIN terms t ON t.id = c.term_id
      WHERE c.crn IS NOT NULL
    SQL

    rows.each do |row|
      new_course = Course
        .joins(:term)
        .find_by(crn: row["crn"].to_i, terms: { uid: row["term_uid"].to_i })
      if new_course
        @course_id_map[row["old_id"].to_i] = new_course.id
      else
        @stats[:courses_not_found] += 1
      end
    end

    log "  Mapped #{@course_id_map.size} courses (#{@stats[:courses_not_found]} not found in new app — run catalog import first)"
  end

  def build_meeting_time_id_map(conn)
    log "Building meeting time ID map..."

    rows = conn.exec(<<~SQL)
      SELECT id AS old_id, course_id AS old_course_id, begin_time, end_time, day_of_week
      FROM meeting_times
      WHERE course_id IS NOT NULL
    SQL

    rows.each do |row|
      new_course_id = @course_id_map[row["old_course_id"].to_i]
      next unless new_course_id

      mt = Course::MeetingTime.find_by(
        course_id: new_course_id,
        begin_time: row["begin_time"]&.to_i,
        end_time: row["end_time"]&.to_i,
        day_of_week: row["day_of_week"]&.to_i
      )
      @meeting_time_id_map[row["old_id"].to_i] = mt.id if mt
    end

    log "  Mapped #{@meeting_time_id_map.size} meeting times"
  end

  # ---------------------------------------------------------------------------
  # Step 1: FinalExams  (term-level catalog data)
  # ---------------------------------------------------------------------------

  def migrate_final_exams(conn)
    log "Migrating final exams..."

    rows = conn.exec(<<~SQL)
      SELECT id, term_id, crn, course_id, exam_date, start_time, end_time,
             location, notes, combined_crns
      FROM final_exams
      ORDER BY term_id, crn
    SQL

    rows.each do |row|
      new_term_id = @term_id_map[row["term_id"].to_i]
      unless new_term_id
        @stats[:final_exams_skipped] += 1
        next
      end

      if @dry_run
        @stats[:final_exams_would_create] += 1
        next
      end

      new_course_id = @course_id_map[row["course_id"].to_i] if row["course_id"]

      exam = FinalExam.find_or_initialize_by(
        crn:     row["crn"]&.to_i,
        term_id: new_term_id
      )
      exam.assign_attributes(
        course_id:     new_course_id,
        exam_date:     row["exam_date"],
        start_time:    row["start_time"].to_i,
        end_time:      row["end_time"].to_i,
        location:      row["location"],
        notes:         row["notes"],
        combined_crns: row["combined_crns"]
      )

      if exam.save
        exam.previously_new_record? ? @stats[:final_exams_created] += 1 : @stats[:final_exams_updated] += 1
      else
        record_error("FinalExam crn=#{row['crn']} term=#{row['term_id']}: #{exam.errors.full_messages.join(', ')}")
        @stats[:final_exams_failed] += 1
      end
    end

    log "  created=#{@stats[:final_exams_created]} updated=#{@stats[:final_exams_updated]} " \
        "skipped=#{@stats[:final_exams_skipped]} failed=#{@stats[:final_exams_failed]}"
  end

  # ---------------------------------------------------------------------------
  # Step 3: Users
  # ---------------------------------------------------------------------------

  def migrate_users(conn)
    log "Migrating users..."

    rows = conn.exec(<<~SQL)
      SELECT u.id, u.first_name, u.last_name, u.access_level,
             u.calendar_token, u.calendar_needs_sync, u.last_calendar_sync_at,
             u.notifications_disabled_until, u.created_at,
             e.email AS primary_email
      FROM users u
      LEFT JOIN emails e ON e.user_id = u.id AND e.primary = TRUE
      ORDER BY u.id
    SQL

    rows.each do |row|
      unless row["primary_email"].present?
        record_error("User #{row['id']}: no primary email — skipped")
        @stats[:users_skipped] += 1
        next
      end

      existing = User.find_by(email: row["primary_email"])
      if existing
        @user_id_map[row["id"].to_i] = existing.id
        @stats[:users_existing] += 1
        next
      end

      if @dry_run
        @user_id_map[row["id"].to_i] = :dry_run
        @stats[:users_would_create] += 1
        next
      end

      user = User.new(
        email:                       row["primary_email"],
        first_name:                  row["first_name"],
        last_name:                   row["last_name"],
        access_level:                row["access_level"].to_i,
        calendar_needs_sync:         pg_bool(row["calendar_needs_sync"]),
        last_calendar_sync_at:       row["last_calendar_sync_at"],
        notifications_disabled_until: row["notifications_disabled_until"]
      )

      # Preserve the existing ICS token so any bookmarked calendar URLs keep working.
      user.calendar_token = row["calendar_token"] if row["calendar_token"].present?

      user.skip_confirmation!
      user.password = SecureRandom.hex(24)

      if user.save
        @user_id_map[row["id"].to_i] = user.id
        @stats[:users_created] += 1
        user.send_reset_password_instructions if @send_welcome_emails
      else
        record_error("User #{row['id']} (#{row['primary_email']}): #{user.errors.full_messages.join(', ')}")
        @stats[:users_failed] += 1
      end
    end

    log "  created=#{@stats[:users_created]} existing=#{@stats[:users_existing]} " \
        "skipped=#{@stats[:users_skipped]} failed=#{@stats[:users_failed]}" \
        "#{@dry_run ? " would_create=#{@stats[:users_would_create]}" : ''}"
  end

  # ---------------------------------------------------------------------------
  # Step 4: OauthCredentials
  # ---------------------------------------------------------------------------

  def migrate_oauth_credentials(conn)
    log "Migrating OAuth credentials..."

    old_user_ids = mapped_old_user_ids
    return log("  No users migrated — skipping") if old_user_ids.empty?

    rows = conn.exec(<<~SQL)
      SELECT id, user_id, provider, uid, email, access_token, refresh_token,
             token_expires_at, metadata, created_at
      FROM oauth_credentials
      WHERE user_id IN (#{old_user_ids.join(',')})
      ORDER BY id
    SQL

    rows.each do |row|
      unless user_mapped?(row["user_id"])
        @stats[:oauth_skipped] += 1
        next
      end

      if @dry_run
        @oauth_id_map[row["id"].to_i] = :dry_run
        @stats[:oauth_would_create] += 1
        next
      end

      new_user_id = resolve_user_id(row["user_id"])
      cred = OauthCredential.find_or_initialize_by(
        provider: row["provider"],
        uid: row["uid"]
      )

      cred.assign_attributes(
        user_id:          new_user_id,
        email:            row["email"],
        access_token:     row["access_token"],
        refresh_token:    row["refresh_token"],
        token_expires_at: row["token_expires_at"],
        metadata:         JSON.parse(row["metadata"] || "{}")
      )

      was_new = cred.new_record?
      if cred.save
        @oauth_id_map[row["id"].to_i] = cred.id
        was_new ? @stats[:oauth_created] += 1 : @stats[:oauth_updated] += 1
      else
        record_error("OauthCredential #{row['id']}: #{cred.errors.full_messages.join(', ')}")
        @stats[:oauth_failed] += 1
      end
    end

    log "  created=#{@stats[:oauth_created]} updated=#{@stats[:oauth_updated]} failed=#{@stats[:oauth_failed]}"
  end

  # ---------------------------------------------------------------------------
  # Step 5: GoogleCalendars
  # ---------------------------------------------------------------------------

  def migrate_google_calendars(conn)
    log "Migrating Google Calendars..."

    old_oauth_ids = @oauth_id_map.keys
    return log("  No OAuth credentials migrated — skipping") if old_oauth_ids.empty?

    rows = conn.exec(<<~SQL)
      SELECT id, oauth_credential_id, google_calendar_id, summary,
             description, time_zone, last_synced_at, created_at
      FROM google_calendars
      WHERE oauth_credential_id IN (#{old_oauth_ids.join(',')})
      ORDER BY id
    SQL

    rows.each do |row|
      unless @oauth_id_map.key?(row["oauth_credential_id"].to_i)
        @stats[:gcal_skipped] += 1
        next
      end

      if @dry_run
        @gcal_id_map[row["id"].to_i] = :dry_run
        @stats[:gcal_would_create] += 1
        next
      end

      new_oauth_id = @oauth_id_map[row["oauth_credential_id"].to_i]
      cal = GoogleCalendar.find_or_initialize_by(google_calendar_id: row["google_calendar_id"])
      cal.assign_attributes(
        oauth_credential_id: new_oauth_id,
        summary:             row["summary"],
        description:         row["description"],
        time_zone:           row["time_zone"],
        last_synced_at:      row["last_synced_at"]
      )

      if cal.save
        @gcal_id_map[row["id"].to_i] = cal.id
        @stats[:gcal_created] += 1
      else
        record_error("GoogleCalendar #{row['id']}: #{cal.errors.full_messages.join(', ')}")
        @stats[:gcal_failed] += 1
      end
    end

    log "  created=#{@stats[:gcal_created]} failed=#{@stats[:gcal_failed]}"
  end

  # ---------------------------------------------------------------------------
  # Step 6: Enrollments
  # ---------------------------------------------------------------------------

  def migrate_enrollments(conn)
    log "Migrating enrollments..."

    old_user_ids = mapped_old_user_ids
    return log("  No users migrated — skipping") if old_user_ids.empty?

    rows = conn.exec(<<~SQL)
      SELECT user_id, course_id
      FROM enrollments
      WHERE user_id IN (#{old_user_ids.join(',')})
    SQL

    rows.each do |row|
      new_course_id = @course_id_map[row["course_id"].to_i]
      unless user_mapped?(row["user_id"]) && new_course_id
        @stats[:enrollments_skipped] += 1
        next
      end

      if @dry_run
        @stats[:enrollments_would_create] += 1
        next
      end

      new_user_id = resolve_user_id(row["user_id"])
      new_term_id = Course.find(new_course_id).term_id
      enrollment = Enrollment.find_or_initialize_by(user_id: new_user_id, course_id: new_course_id, term_id: new_term_id)
      if enrollment.new_record?
        if enrollment.save
          @stats[:enrollments_created] += 1
        else
          record_error("Enrollment user=#{new_user_id} course=#{new_course_id}: #{enrollment.errors.full_messages.join(', ')}")
          @stats[:enrollments_failed] += 1
        end
      else
        @stats[:enrollments_existing] += 1
      end
    end

    log "  created=#{@stats[:enrollments_created]} existing=#{@stats[:enrollments_existing]} " \
        "skipped=#{@stats[:enrollments_skipped]} failed=#{@stats[:enrollments_failed]}"
  end

  # ---------------------------------------------------------------------------
  # Step 7: CalendarPreferences
  # ---------------------------------------------------------------------------

  def migrate_calendar_preferences(conn)
    log "Migrating calendar preferences..."

    old_user_ids = mapped_old_user_ids
    return log("  No users migrated — skipping") if old_user_ids.empty?

    rows = conn.exec(<<~SQL)
      SELECT user_id, scope, event_type, color_id, title_template,
             description_template, location_template, visibility,
             reminder_settings
      FROM calendar_preferences
      WHERE user_id IN (#{old_user_ids.join(',')})
    SQL

    rows.each do |row|
      unless user_mapped?(row["user_id"])
        @stats[:cal_prefs_skipped] += 1
        next
      end

      if @dry_run
        @stats[:cal_prefs_would_create] += 1
        next
      end

      new_user_id = resolve_user_id(row["user_id"])
      pref = CalendarPreference.find_or_initialize_by(
        user_id:    new_user_id,
        scope:      row["scope"].to_i,
        event_type: row["event_type"]
      )
      pref.assign_attributes(
        color_id:             row["color_id"]&.to_i,
        title_template:       row["title_template"],
        description_template: row["description_template"],
        location_template:    row["location_template"],
        visibility:           row["visibility"],
        reminder_settings:    JSON.parse(row["reminder_settings"] || "[]")
      )

      if pref.save
        @stats[:cal_prefs_created] += 1
      else
        record_error("CalendarPreference user=#{new_user_id}: #{pref.errors.full_messages.join(', ')}")
        @stats[:cal_prefs_failed] += 1
      end
    end

    log "  created=#{@stats[:cal_prefs_created]} failed=#{@stats[:cal_prefs_failed]}"
  end

  # ---------------------------------------------------------------------------
  # Step 8: EventPreferences
  # ---------------------------------------------------------------------------

  def migrate_event_preferences(conn)
    log "Migrating event preferences..."

    old_user_ids = mapped_old_user_ids
    return log("  No users migrated — skipping") if old_user_ids.empty?

    rows = conn.exec(<<~SQL)
      SELECT user_id, preferenceable_type, preferenceable_id, color_id,
             title_template, description_template, location_template,
             visibility, reminder_settings
      FROM event_preferences
      WHERE user_id IN (#{old_user_ids.join(',')})
    SQL

    rows.each do |row|
      unless user_mapped?(row["user_id"])
        @stats[:event_prefs_skipped] += 1
        next
      end

      new_type, new_id = map_preferenceable(row["preferenceable_type"], row["preferenceable_id"].to_i)
      unless new_type && new_id
        @stats[:event_prefs_skipped] += 1
        next
      end

      if @dry_run
        @stats[:event_prefs_would_create] += 1
        next
      end

      new_user_id = resolve_user_id(row["user_id"])
      pref = EventPreference.find_or_initialize_by(
        user_id:            new_user_id,
        preferenceable_type: new_type,
        preferenceable_id:  new_id
      )
      pref.assign_attributes(
        color_id:             row["color_id"]&.to_i,
        title_template:       row["title_template"],
        description_template: row["description_template"],
        location_template:    row["location_template"],
        visibility:           row["visibility"],
        reminder_settings:    JSON.parse(row["reminder_settings"] || "null")
      )

      if pref.save
        @stats[:event_prefs_created] += 1
      else
        record_error("EventPreference user=#{new_user_id}: #{pref.errors.full_messages.join(', ')}")
        @stats[:event_prefs_failed] += 1
      end
    end

    log "  created=#{@stats[:event_prefs_created]} skipped=#{@stats[:event_prefs_skipped]} " \
        "failed=#{@stats[:event_prefs_failed]}"
  end

  # ---------------------------------------------------------------------------
  # Step 9: UserExtensionConfigs
  # ---------------------------------------------------------------------------

  def migrate_user_extension_configs(conn)
    log "Migrating user extension configs..."

    old_user_ids = mapped_old_user_ids
    return log("  No users migrated — skipping") if old_user_ids.empty?

    rows = conn.exec(<<~SQL)
      SELECT user_id, military_time, advanced_editing, sync_university_events,
             university_event_categories, default_color_lecture, default_color_lab
      FROM user_extension_configs
      WHERE user_id IN (#{old_user_ids.join(',')})
    SQL

    rows.each do |row|
      unless user_mapped?(row["user_id"])
        @stats[:ext_configs_skipped] += 1
        next
      end

      if @dry_run
        @stats[:ext_configs_would_update] += 1
        next
      end

      new_user_id = resolve_user_id(row["user_id"])
      # User#after_create already built an empty config; update it.
      config = UserExtensionConfig.find_or_initialize_by(user_id: new_user_id)
      config.assign_attributes(
        military_time:               pg_bool(row["military_time"]),
        advanced_editing:            pg_bool(row["advanced_editing"]),
        sync_university_events:      pg_bool(row["sync_university_events"]),
        university_event_categories: JSON.parse(row["university_event_categories"] || "[]"),
        default_color_lecture:       row["default_color_lecture"] || "#039be5",
        default_color_lab:           row["default_color_lab"] || "#f6bf26"
      )

      if config.save
        @stats[:ext_configs_updated] += 1
      else
        record_error("UserExtensionConfig user=#{new_user_id}: #{config.errors.full_messages.join(', ')}")
        @stats[:ext_configs_failed] += 1
      end
    end

    log "  updated=#{@stats[:ext_configs_updated]} failed=#{@stats[:ext_configs_failed]}"
  end

  # ---------------------------------------------------------------------------
  # Step 10: Friendships
  # ---------------------------------------------------------------------------

  def migrate_friendships(conn)
    log "Migrating friendships..."

    old_user_ids = mapped_old_user_ids
    return log("  No users migrated — skipping") if old_user_ids.empty?

    # Only migrate friendships where BOTH sides are migrated.
    rows = conn.exec(<<~SQL)
      SELECT requester_id, addressee_id, status
      FROM friendships
      WHERE requester_id IN (#{old_user_ids.join(',')})
        AND addressee_id IN (#{old_user_ids.join(',')})
    SQL

    rows.each do |row|
      raw_status = row["status"].to_i
      # Only migrate statuses the new app's enum recognises (pending=0, accepted=1).
      unless [ 0, 1 ].include?(raw_status)
        @stats[:friendships_skipped] += 1
        next
      end

      unless user_mapped?(row["requester_id"]) && user_mapped?(row["addressee_id"])
        @stats[:friendships_skipped] += 1
        next
      end

      if @dry_run
        @stats[:friendships_would_create] += 1
        next
      end

      new_requester = resolve_user_id(row["requester_id"])
      new_addressee = resolve_user_id(row["addressee_id"])

      friendship = Friendship.find_or_initialize_by(
        requester_id: new_requester,
        addressee_id: new_addressee
      )

      if friendship.new_record?
        friendship.status = raw_status
        if friendship.save
          @stats[:friendships_created] += 1
        else
          record_error("Friendship #{new_requester}→#{new_addressee}: #{friendship.errors.full_messages.join(', ')}")
          @stats[:friendships_failed] += 1
        end
      else
        @stats[:friendships_existing] += 1
      end
    end

    log "  created=#{@stats[:friendships_created]} existing=#{@stats[:friendships_existing]} " \
        "skipped=#{@stats[:friendships_skipped]} failed=#{@stats[:friendships_failed]}"
  end

  # ---------------------------------------------------------------------------
  # Step 11: Flipper feature flags
  # ---------------------------------------------------------------------------

  def migrate_flipper(conn)
    log "Migrating Flipper feature flags..."

    unless ActiveRecord::Base.connection.table_exists?("flipper_features")
      log "  flipper_features table not found — run migrations first, skipping"
      return
    end

    rows = conn.exec("SELECT key, created_at, updated_at FROM flipper_features ORDER BY key")
    rows.each do |row|
      next if @dry_run && @stats[:flipper_features_would_upsert] += 1

      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO flipper_features (key, created_at, updated_at)
        VALUES (#{conn.escape_literal(row['key'])}, NOW(), NOW())
        ON CONFLICT (key) DO NOTHING
      SQL
      @stats[:flipper_features_upserted] += 1
    end

    gate_rows = conn.exec(<<~SQL)
      SELECT feature_key, key, value, created_at, updated_at FROM flipper_gates ORDER BY feature_key, key
    SQL
    gate_rows.each do |row|
      next if @dry_run && @stats[:flipper_gates_would_upsert] += 1

      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO flipper_gates (feature_key, key, value, created_at, updated_at)
        VALUES (
          #{conn.escape_literal(row['feature_key'])},
          #{conn.escape_literal(row['key'])},
          #{row['value'] ? conn.escape_literal(row['value']) : 'NULL'},
          NOW(), NOW()
        )
        ON CONFLICT (feature_key, key, value) WHERE value IS NOT NULL DO NOTHING
      SQL
      @stats[:flipper_gates_upserted] += 1
    end

    log "  features=#{@stats[:flipper_features_upserted]} gates=#{@stats[:flipper_gates_upserted]}"
  end

  # ---------------------------------------------------------------------------
  # Step 12: Blazer queries, dashboards, and checks
  # ---------------------------------------------------------------------------

  def migrate_blazer(conn)
    log "Migrating Blazer queries and dashboards..."

    unless ActiveRecord::Base.connection.table_exists?("blazer_queries")
      log "  blazer_queries table not found — run migrations first, skipping"
      return
    end

    # Queries — map creator_id to new user IDs
    query_id_map = {}  # old blazer_query.id => new blazer_query.id

    rows = conn.exec(<<~SQL)
      SELECT id, name, description, statement, data_source, status, creator_id, created_at, updated_at
      FROM blazer_queries ORDER BY id
    SQL
    rows.each do |row|
      if @dry_run
        @stats[:blazer_queries_would_create] += 1
        next
      end

      new_creator_id = row["creator_id"] ? resolve_user_id(row["creator_id"]) : nil

      result = ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO blazer_queries (name, description, statement, data_source, status, creator_id, created_at, updated_at)
        VALUES (
          #{conn.escape_literal(row['name'] || '')},
          #{row['description'] ? conn.escape_literal(row['description']) : 'NULL'},
          #{row['statement'] ? conn.escape_literal(row['statement']) : 'NULL'},
          #{row['data_source'] ? conn.escape_literal(row['data_source']) : 'NULL'},
          #{row['status'] ? conn.escape_literal(row['status']) : 'NULL'},
          #{new_creator_id || 'NULL'},
          NOW(), NOW()
        )
        RETURNING id
      SQL
      query_id_map[row["id"].to_i] = result.first["id"].to_i
      @stats[:blazer_queries_created] += 1
    end

    # Dashboards
    dashboard_id_map = {}

    rows = conn.exec("SELECT id, name, creator_id, created_at, updated_at FROM blazer_dashboards ORDER BY id")
    rows.each do |row|
      if @dry_run
        @stats[:blazer_dashboards_would_create] += 1
        next
      end

      new_creator_id = row["creator_id"] ? resolve_user_id(row["creator_id"]) : nil

      result = ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO blazer_dashboards (name, creator_id, created_at, updated_at)
        VALUES (
          #{conn.escape_literal(row['name'] || '')},
          #{new_creator_id || 'NULL'},
          NOW(), NOW()
        )
        RETURNING id
      SQL
      dashboard_id_map[row["id"].to_i] = result.first["id"].to_i
      @stats[:blazer_dashboards_created] += 1
    end

    # Dashboard-query join rows
    rows = conn.exec("SELECT dashboard_id, query_id, position FROM blazer_dashboard_queries")
    rows.each do |row|
      new_dashboard_id = dashboard_id_map[row["dashboard_id"].to_i]
      new_query_id     = query_id_map[row["query_id"].to_i]
      next unless new_dashboard_id && new_query_id
      next if @dry_run

      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO blazer_dashboard_queries (dashboard_id, query_id, position, created_at, updated_at)
        VALUES (#{new_dashboard_id}, #{new_query_id}, #{row['position'] || 0}, NOW(), NOW())
        ON CONFLICT DO NOTHING
      SQL
    end

    # Checks
    rows = conn.exec(<<~SQL)
      SELECT query_id, creator_id, check_type, emails, schedule,
             slack_channels, state, last_run_at, created_at, updated_at
      FROM blazer_checks ORDER BY id
    SQL
    rows.each do |row|
      new_query_id   = query_id_map[row["query_id"].to_i] if row["query_id"]
      next unless new_query_id

      if @dry_run
        @stats[:blazer_checks_would_create] += 1
        next
      end

      new_creator_id = row["creator_id"] ? resolve_user_id(row["creator_id"]) : nil

      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO blazer_checks (query_id, creator_id, check_type, emails, schedule,
                                   slack_channels, state, last_run_at, created_at, updated_at)
        VALUES (
          #{new_query_id},
          #{new_creator_id || 'NULL'},
          #{row['check_type'] ? conn.escape_literal(row['check_type']) : 'NULL'},
          #{row['emails'] ? conn.escape_literal(row['emails']) : 'NULL'},
          #{row['schedule'] ? conn.escape_literal(row['schedule']) : 'NULL'},
          #{row['slack_channels'] ? conn.escape_literal(row['slack_channels']) : 'NULL'},
          #{row['state'] ? conn.escape_literal(row['state']) : 'NULL'},
          #{row['last_run_at'] ? conn.escape_literal(row['last_run_at']) : 'NULL'},
          NOW(), NOW()
        )
      SQL
      @stats[:blazer_checks_created] += 1
    end

    log "  queries=#{@stats[:blazer_queries_created]} dashboards=#{@stats[:blazer_dashboards_created]} " \
        "checks=#{@stats[:blazer_checks_created]}"
  end

  # ---------------------------------------------------------------------------
  # Step 13: Enrichment jobs
  # ---------------------------------------------------------------------------

  def queue_enrichment
    log "Queuing enrichment jobs..."

    new_user_ids = @user_id_map.values.reject { |v| v == :dry_run }
    return log("  No users to enrich") if new_user_ids.empty?

    # Mark all migrated users for sync so the nightly job picks them up.
    User.where(id: new_user_ids).update_all(calendar_needs_sync: true)

    # Queue GCal sync for users who brought their OAuth tokens.
    oauth_user_ids = OauthCredential
      .where(user_id: new_user_ids, provider: "google")
      .pluck(:user_id)
      .uniq

    oauth_user_ids.each do |uid|
      user = User.find_by(id: uid)
      GoogleCalendarSyncJob.perform_later(user) if user
    end
    @stats[:sync_jobs_queued] = oauth_user_ids.size

    # Queue RMP rating refresh for all faculty teaching enrolled courses.
    enrolled_course_ids = Enrollment
      .where(user_id: new_user_ids)
      .pluck(:course_id)
      .uniq

    faculty_ids = Course
      .joins(:faculties)
      .where(id: enrolled_course_ids)
      .pluck("faculties.id")
      .uniq

    faculty_ids.each { |fid| UpdateFacultyRatingsJob.perform_later(fid) }
    @stats[:faculty_rating_jobs_queued] = faculty_ids.size

    log "  sync_jobs=#{@stats[:sync_jobs_queued]} faculty_rating_jobs=#{@stats[:faculty_rating_jobs_queued]}"
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def mapped_old_user_ids
    @user_id_map.keys
  end

  def user_mapped?(old_id)
    @user_id_map.key?(old_id.to_i)
  end

  def resolve_user_id(old_id)
    result = @user_id_map[old_id.to_i]
    result == :dry_run ? nil : result
  end

  def map_preferenceable(type, old_id)
    case type
    when "MeetingTime"
      new_id = @meeting_time_id_map[old_id]
      new_id ? [ "Course::MeetingTime", new_id ] : nil
    when "Course"
      new_id = @course_id_map[old_id]
      new_id ? [ "Course", new_id ] : nil
    else
      nil
    end
  end

  def pg_bool(val)
    val == "t" || val == true
  end

  def record_error(msg)
    @errors << msg
    warn "  WARN: #{msg}"
  end

  def log(msg)
    puts "[#{Time.current.strftime('%H:%M:%S')}] #{msg}"
  end

  def report
    puts "\n#{'=' * 60}"
    puts "Import complete (dry_run=#{@dry_run})"
    puts "=" * 60
    @stats.sort.each { |k, v| printf "  %-42s %d\n", k, v }

    if @errors.any?
      puts "\nErrors (#{@errors.size}):"
      @errors.first(20).each { |e| puts "  #{e}" }
      puts "  ... (#{@errors.size - 20} more)" if @errors.size > 20
    end
  end
end
