# db/migrate/20250214001455_make_emails_case_insensitive.rb
class MakeEmailsCaseInsensitive < ActiveRecord::Migration[7.2]
  def up
    # 1) Find duplicates ignoring case => group by LOWER(email)
    duplicates = User
      .group("LOWER(email)")
      .having("COUNT(*) > 1")
      .count

    duplicates.each do |lower_email, _count|
      # Convert the relation to an array
      users = User.where("LOWER(email) = ?", lower_email).order(:id).to_a

      # Keep the first user as-is => rename or remove duplicates
      first_user = users.shift
      users.each do |u|
        # rename them to e.g. "123_some@email.com"
        new_email = "#{u.id}_#{u.email}"
        u.update_column(:email, new_email) # skip validations
      end
    end

    # 2) Downcase every email
    User.find_each do |u|
      u.update_column(:email, u.email.downcase)
    end

    # 3) Remove existing unique index on :email if it exists
    if index_exists?(:users, :email, unique: true)
      remove_index :users, :email
    end

    # 4) Create the new unique index on LOWER(email)
    execute <<~SQL
      CREATE UNIQUE INDEX index_users_on_lower_email
      ON users (LOWER(email));
    SQL
  end

  def down
    execute <<~SQL
      DROP INDEX IF EXISTS index_users_on_lower_email;
    SQL
    # Optionally re-add the old index:
    # add_index :users, :email, unique: true
  end
end
