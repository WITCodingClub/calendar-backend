# frozen_string_literal: true

# Backs the app-level has_one uniqueness validations with real DB constraints,
# so concurrent requests can't slip duplicate rows past a check-then-act.
#
# Each index is preceded by a conservative de-dup that keeps the earliest row
# (lowest id) of any existing duplicate group, using raw SQL delete to avoid
# firing destroy callbacks (notably GoogleCalendar#before_destroy, which would
# delete the remote Google calendar). Orphaned child rows left behind by removed
# google_calendars are handled by the existing orphan-cleanup jobs.
class EnforceHasOneUniqueness < ActiveRecord::Migration[8.1]
  def up
    # --- user_extension_configs: one per user ------------------------------
    dedupe("user_extension_configs", "user_id")
    add_index :user_extension_configs, :user_id, unique: true,
              name: "index_user_extension_configs_on_user_id_unique"
    remove_index :user_extension_configs, name: "index_user_extension_configs_on_user_id", if_exists: true

    # --- google_calendars: one course calendar per oauth credential --------
    dedupe("google_calendars", "oauth_credential_id")
    add_index :google_calendars, :oauth_credential_id, unique: true,
              name: "index_google_calendars_on_oauth_credential_id_unique"
    remove_index :google_calendars, name: "index_google_calendars_on_oauth_credential_id", if_exists: true

    # --- calendar_preferences: one global preference per user --------------
    # Partial unique index — the existing (user_id, scope, event_type) index
    # can't enforce this because event_type is NULL for global rows.
    execute(<<~SQL)
      DELETE FROM calendar_preferences a
      USING calendar_preferences b
      WHERE a.scope = 0 AND b.scope = 0
        AND a.user_id = b.user_id
        AND a.id > b.id;
    SQL
    add_index :calendar_preferences, :user_id, unique: true,
              where: "scope = 0",
              name: "index_calendar_prefs_one_global_per_user"

    # --- friendships: one friendship per unordered user pair ---------------
    # Functional index on the sorted pair blocks both (A,B) and its reverse (B,A).
    execute(<<~SQL)
      DELETE FROM friendships a
      USING friendships b
      WHERE LEAST(a.requester_id, a.addressee_id) = LEAST(b.requester_id, b.addressee_id)
        AND GREATEST(a.requester_id, a.addressee_id) = GREATEST(b.requester_id, b.addressee_id)
        AND a.id > b.id;
    SQL
    execute(<<~SQL)
      CREATE UNIQUE INDEX index_friendships_on_unordered_pair
      ON friendships (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id));
    SQL
  end

  def down
    execute("DROP INDEX IF EXISTS index_friendships_on_unordered_pair;")
    remove_index :calendar_preferences, name: "index_calendar_prefs_one_global_per_user", if_exists: true

    add_index :google_calendars, :oauth_credential_id,
              name: "index_google_calendars_on_oauth_credential_id", if_not_exists: true
    remove_index :google_calendars, name: "index_google_calendars_on_oauth_credential_id_unique", if_exists: true

    add_index :user_extension_configs, :user_id,
              name: "index_user_extension_configs_on_user_id", if_not_exists: true
    remove_index :user_extension_configs, name: "index_user_extension_configs_on_user_id_unique", if_exists: true
  end

  private

  # Deletes duplicate rows for a column, keeping the lowest id in each group.
  # Uses raw SQL delete so no ActiveRecord destroy callbacks fire.
  def dedupe(table, column)
    execute(<<~SQL)
      DELETE FROM #{table} a
      USING #{table} b
      WHERE a.#{column} = b.#{column}
        AND a.id > b.id;
    SQL
  end
end
