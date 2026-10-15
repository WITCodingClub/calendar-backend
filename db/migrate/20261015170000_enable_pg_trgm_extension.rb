# frozen_string_literal: true

# pg_trgm lets a GIN index serve ILIKE '%q%' searches (#684). It is a contrib
# extension, so postgres:17-alpine and the production image already ship it.
class EnablePgTrgmExtension < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
  end
end
