# frozen_string_literal: true

class ValidateForeignKeyConstraints < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute "ALTER TABLE rating_distributions VALIDATE CONSTRAINT fk_rails_2e90d30a95;"
      execute "ALTER TABLE related_professors VALIDATE CONSTRAINT fk_rails_d6efdd328d;"
      execute "ALTER TABLE related_professors VALIDATE CONSTRAINT fk_rails_29ff12d592;"
      execute "ALTER TABLE teacher_rating_tags VALIDATE CONSTRAINT fk_rails_d163e0a6d7;"
      execute "ALTER TABLE rmp_ratings VALIDATE CONSTRAINT fk_rails_e92e4d6188;"
    end
  end

  def down
    # Can't un-validate constraints, but they'll remain valid
  end

end
