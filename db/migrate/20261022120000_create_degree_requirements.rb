# frozen_string_literal: true

# Degree requirements from the academic catalog (#526). One catalog year
# holds a requirement set for each program. A requirement set has the plans
# of study (the courses for each semester) and the elective lists that the
# plans name. docs/degree-requirements.md describes the tables.
class CreateDegreeRequirements < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_years do |t|
      t.integer :start_year, null: false
      t.string :source, null: false, default: "html"
      t.string :status, null: false, default: "pending"
      t.string :base_url
      t.datetime :imported_at
      t.timestamps
      t.index :start_year, unique: true
      t.check_constraint "start_year >= 2010", name: "catalog_years_start_year_plausible"
    end

    create_table :degree_programs do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :kind, null: false
      t.string :level, null: false
      t.references :parent_program, foreign_key: { to_table: :degree_programs, on_delete: :nullify }
      t.timestamps
      t.index :slug, unique: true
    end

    create_table :requirement_sets do |t|
      t.references :degree_program, null: false, foreign_key: true, index: false
      t.references :catalog_year, null: false, foreign_key: true
      t.string :name, null: false
      t.string :path
      t.string :school_name
      t.string :department_name
      t.text :description
      t.integer :total_credits
      t.string :source, null: false, default: "html"
      t.boolean :needs_review, null: false, default: false
      t.string :source_digest
      t.datetime :fetched_at
      t.datetime :last_seen_at
      t.timestamps
      t.index [ :degree_program_id, :catalog_year_id ], unique: true
    end

    create_table :program_plans do |t|
      t.references :requirement_set, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.integer :years, null: false
      t.boolean :accelerated, null: false, default: false
      t.integer :total_credits
      t.timestamps
      t.index [ :requirement_set_id, :position ], unique: true
      t.check_constraint "years BETWEEN 1 AND 6", name: "program_plans_years_range"
    end

    create_table :elective_groups do |t|
      t.references :requirement_set, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :program_plan, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :heading
      t.integer :min_courses
      t.integer :min_credits
      t.integer :position, null: false, default: 0
      t.text :notes
      t.timestamps
      # The key a re-import upserts on. A list printed once for the whole
      # program has no plan, so the nulls count as equal.
      t.index [ :requirement_set_id, :program_plan_id, :position ], unique: true, nulls_not_distinct: true,
                                                                    name: "idx_elective_groups_unique"
    end

    create_table :elective_group_courses do |t|
      t.references :elective_group, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :subject_code, null: false
      t.integer :course_number, null: false
      t.references :catalog_course, foreign_key: { on_delete: :nullify }
      t.boolean :requires_approval, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [ :elective_group_id, :subject_code, :course_number ], unique: true,
                                                                     name: "idx_elective_group_courses_unique"
      t.index [ :subject_code, :course_number ]
    end

    create_table :program_plan_items do |t|
      t.references :program_plan, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :year_index, null: false
      t.string :season, null: false
      t.integer :position, null: false
      t.string :kind, null: false
      t.string :subject_code
      t.integer :course_number
      t.references :catalog_course, foreign_key: { on_delete: :nullify }
      t.string :label
      t.integer :min_credits
      t.integer :max_credits
      t.integer :lecture_hours
      t.integer :lab_hours
      t.references :elective_group, foreign_key: { on_delete: :nullify }
      t.string :footnote
      t.jsonb :options, null: false, default: []
      t.timestamps
      t.index [ :program_plan_id, :position ], unique: true
      t.index [ :subject_code, :course_number ]
      t.check_constraint "year_index >= 1", name: "program_plan_items_year_index_positive"
    end
  end
end
