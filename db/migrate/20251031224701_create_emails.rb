class CreateEmails < ActiveRecord::Migration[8.1]
  def up
    create_table :emails do |t|
      t.string :email, null: false
      t.boolean :primary, default: false

      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    # add constraint to user only has one primary email
    add_index :emails, [:user_id, :primary], unique: true, where: "\"primary\" = true"


    # migrate existing user emails to email table
    # for each user, create an email record with their email
    User.reset_column_information
    User.find_each do |user|
      Email.create!(email: user.email, primary: true, user_id: user.id)
    end

    # remove email column from users table
    safety_assured { remove_column :users, :email }

  end

  def down
    # add email column back to users table
    add_column :users, :email, :string, null: false, default: ""

    # migrate emails back to users table
    Email.reset_column_information
    Email.where(primary: true).find_each do |email_record|
      user = User.find(email_record.user_id)
      user.update!(email: email_record.email)
    end

    # drop emails table
    drop_table :emails
  end

end
