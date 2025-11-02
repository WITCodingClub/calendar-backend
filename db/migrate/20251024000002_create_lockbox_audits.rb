class CreateLockboxAudits < ActiveRecord::Migration[8.1]
  def change
    create_table :lockbox_audits do |t|
      t.references :subject, polymorphic: true
      t.references :viewer, polymorphic: true
      t.jsonb :data
      t.string :context
      t.string :ip
      t.datetime :created_at
    end
  end
end
