# frozen_string_literal: true

# PgHero reads query stats from pg_stat_statements. The view only returns rows
# when the server also loads the library through shared_preload_libraries,
# which the infra repo sets on the wit-calendar-db container.
class EnablePgStatStatements < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_stat_statements"
  end
end
