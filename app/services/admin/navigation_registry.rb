# frozen_string_literal: true

module Admin
  # The admin sections, in the order the sidebar and the command palette show
  # them. `icon` is a name from Admin::ApplicationHelper::ICONS.
  class NavigationRegistry
    CATEGORIES = [
      {
        id: :overview, title: "Overview", min_role: :admin,
        items: [
          { id: :dashboard, title: "Dashboard", path: :admin_root_path, icon: :home,
            description: "Key counts, sync health, and failed jobs", keywords: [ "stats", "overview", "home" ] }
        ]
      },
      {
        id: :people, title: "People", min_role: :admin,
        items: [
          { id: :users, title: "Users", path: :admin_users_path, icon: :users,
            description: "Manage user accounts and permissions", keywords: [ "accounts", "permissions" ] }
        ]
      },
      {
        id: :academics, title: "Academics", min_role: :admin,
        items: [
          { id: :terms, title: "Terms", path: :admin_terms_path, icon: :clock,
            description: "View academic terms", keywords: [ "semester", "fall", "spring", "summer" ], read_only: true },
          { id: :courses, title: "Courses", path: :admin_courses_path, icon: :book,
            description: "View courses", keywords: [ "classes", "schedule" ] },
          { id: :course_catalog, title: "Course Catalog", path: :admin_course_catalog_path, icon: :download,
            description: "Import courses from LeopardWeb", keywords: [ "import", "leopardweb", "catalog" ], min_role: :super_admin },
          { id: :faculty, title: "Faculty", path: :admin_faculties_path, icon: :academic_cap,
            description: "Manage faculty and RMP ratings", keywords: [ "professors", "instructors" ] },
          { id: :rmp_ratings, title: "RMP Ratings", path: :admin_rmp_ratings_path, icon: :star,
            description: "View Rate My Professor ratings", keywords: [ "rate my professor" ], read_only: true },
          { id: :finals_schedules, title: "Finals Schedules", path: :admin_finals_schedules_path, icon: :clipboard_check,
            description: "Manage finals exam schedules", keywords: [ "exams", "finals" ] }
        ]
      },
      {
        id: :campus, title: "Campus", min_role: :admin,
        items: [
          { id: :buildings, title: "Buildings", path: :admin_buildings_path, icon: :building,
            description: "Compare and reconcile LeopardWeb vs 25Live building names", keywords: [ "buildings", "rooms", "location", "25live" ] },
          { id: :rooms, title: "Rooms", path: :admin_rooms_path, icon: :location,
            description: "Browse rooms and their scheduled courses", keywords: [ "rooms", "classrooms", "locations" ], read_only: true }
        ]
      },
      {
        id: :calendars, title: "Calendars", min_role: :admin,
        items: [
          { id: :course_calendars, title: "Calendars", path: :admin_calendars_path, icon: :calendar,
            description: "View synced course calendars", keywords: [ "google", "microsoft", "calendars" ] },
          { id: :calendar_events, title: "Calendar Events", path: :admin_calendar_events_path, icon: :refresh,
            description: "View synced calendar events", keywords: [ "events", "sync" ], read_only: true },
          { id: :university_events, title: "University Events", path: :admin_university_calendar_events_path, icon: :flag,
            description: "Manage university-wide calendar events", keywords: [ "holidays", "breaks", "events" ] }
        ]
      },
      # `external: true` marks a mounted engine with its own layout. The admin
      # nav opens it in a new tab, so the admin dashboard stays open.
      {
        id: :system_tools, title: "System", min_role: :super_admin,
        items: [
          { id: :service_account, title: "Service Account", path: :admin_service_account_index_path, icon: :key,
            description: "Manage Google service account OAuth", keywords: [ "service account", "oauth", "google" ], min_role: :owner },
          { id: :jobs, title: "Background Jobs", path: :admin_mission_control_jobs_path, icon: :collection, external: true,
            description: "Monitor and manage background jobs", keywords: [ "jobs", "queues", "workers", "solid_queue" ], min_role: :super_admin },
          { id: :feature_flags, title: "Feature Flags", path: "/admin/flipper", icon: :adjustments, external: true,
            description: "Toggle feature flags with Flipper", keywords: [ "flipper", "flags", "features" ], min_role: :super_admin },
          { id: :sql, title: "SQL Queries", path: :admin_blazer_path, icon: :code, external: true,
            description: "Run ad-hoc SQL queries with Blazer", keywords: [ "blazer", "sql", "queries", "database" ], min_role: :super_admin },
          { id: :database, title: "Database", path: :admin_pg_hero_path, icon: :database, external: true,
            description: "PostgreSQL insights and performance via PgHero", keywords: [ "postgres", "pghero", "database", "queries" ], min_role: :super_admin },
          { id: :console_audits, title: "Console Audits", path: :admin_audits1984_path, icon: :shield_check, external: true,
            description: "Audit trail of Rails console sessions", keywords: [ "audits", "console", "security" ], min_role: :owner }
        ]
      }
    ].freeze

    def self.categories_for(user)
      CATEGORIES.select { |c| user_has_access?(user, c[:min_role] || :admin) }.map do |category|
        { **category, items: items_for(user, category[:items]) }
      end
    end

    def self.items_for_user(user)
      CATEGORIES.flat_map { |c| items_for(user, c[:items]) }.compact
    end

    # One item by id, or nil when the user may not see it.
    def self.item_for(user, id)
      items_for_user(user).find { |item| item[:id] == id }
    end

    def self.user_has_access?(user, min_role)
      return false unless user

      levels = { user: 0, admin: 1, super_admin: 2, owner: 3 }
      (levels[user.access_level.to_sym] || 0) >= (levels[min_role.to_sym] || 0)
    end

    def self.items_for(user, items)
      items.select { |item| user_has_access?(user, item[:min_role] || :admin) }
    end
  end
end
