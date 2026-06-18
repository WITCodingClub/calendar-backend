# frozen_string_literal: true

module Admin
  class NavigationRegistry
    CATEGORIES = [
      {
        id: :overview, title: "Overview", min_role: :admin,
        items: [
          { id: :dashboard, title: "Dashboard", path: :admin_root_path,
            description: "System overview and statistics", keywords: [ "stats", "overview", "home" ] }
        ]
      },
      {
        id: :user_management, title: "User Management", min_role: :admin,
        items: [
          { id: :users, title: "Users", path: :admin_users_path,
            description: "Manage user accounts and permissions", keywords: [ "accounts", "permissions" ] },
          { id: :google_calendars, title: "Google Calendars", path: :admin_calendars_path,
            description: "View user Google Calendars", keywords: [ "google", "calendars" ] }
        ]
      },
      {
        id: :academic_data, title: "Academic Data", min_role: :admin,
        items: [
          { id: :courses, title: "Courses", path: :admin_courses_path,
            description: "View courses", keywords: [ "classes", "schedule" ] },
          { id: :faculty, title: "Faculty", path: :admin_faculties_path,
            description: "Manage faculty and RMP ratings", keywords: [ "professors", "instructors" ] },
          { id: :terms, title: "Terms", path: :admin_terms_path,
            description: "View academic terms", keywords: [ "semester", "fall", "spring", "summer" ], read_only: true },
          { id: :rooms, title: "Rooms", path: :admin_rooms_path,
            description: "Browse rooms and their scheduled courses", keywords: [ "rooms", "classrooms", "locations" ], read_only: true }
        ]
      },
      {
        id: :schedules_calendars, title: "Schedules & Calendars", min_role: :admin,
        items: [
          { id: :finals_schedules, title: "Finals Schedules", path: :admin_finals_schedules_path,
            description: "Manage finals exam schedules", keywords: [ "exams", "finals" ] },
          { id: :university_events, title: "University Events", path: :admin_university_calendar_events_path,
            description: "Manage university-wide calendar events", keywords: [ "holidays", "breaks", "events" ] },
          { id: :google_calendar_events, title: "Google Calendar Events", path: :admin_google_calendar_events_path,
            description: "View synced calendar events", keywords: [ "events", "sync" ], read_only: true }
        ]
      },
      {
        id: :data_sources, title: "Data Sources", min_role: :admin,
        items: [
          { id: :course_catalog, title: "Course Catalog", path: :admin_course_catalog_path,
            description: "Import courses from LeopardWeb", keywords: [ "import", "leopardweb", "catalog" ], min_role: :super_admin },
          { id: :buildings, title: "Buildings", path: :admin_buildings_path,
            description: "Compare and reconcile LeopardWeb vs 25Live building names", keywords: [ "buildings", "rooms", "location", "25live" ] },
          { id: :rmp_ratings, title: "RMP Ratings", path: :admin_rmp_ratings_path,
            description: "View Rate My Professor ratings", keywords: [ "rate my professor" ], read_only: true }
        ]
      },
      {
        id: :system_tools, title: "System Tools", min_role: :super_admin,
        items: [
          { id: :jobs, title: "Background Jobs", path: :admin_mission_control_jobs_path,
            description: "Monitor and manage background jobs", keywords: [ "jobs", "queues", "workers", "solid_queue" ], min_role: :super_admin },
          { id: :feature_flags, title: "Feature Flags", path: "/admin/flipper",
            description: "Toggle feature flags with Flipper", keywords: [ "flipper", "flags", "features" ], min_role: :super_admin },
          { id: :sql, title: "SQL Queries", path: :admin_blazer_path,
            description: "Run ad-hoc SQL queries with Blazer", keywords: [ "blazer", "sql", "queries", "database" ], min_role: :super_admin },
          { id: :database, title: "Database", path: :admin_pg_hero_path,
            description: "PostgreSQL insights and performance via PgHero", keywords: [ "postgres", "pghero", "database", "queries" ], min_role: :super_admin },
          { id: :console_audits, title: "Console Audits", path: :admin_audits1984_path,
            description: "Audit trail of Rails console sessions", keywords: [ "audits", "console", "security" ], min_role: :owner },
          { id: :service_account, title: "Service Account", path: :admin_service_account_index_path,
            description: "Manage Google service account OAuth", keywords: [ "service account", "oauth", "google" ], min_role: :owner }
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
