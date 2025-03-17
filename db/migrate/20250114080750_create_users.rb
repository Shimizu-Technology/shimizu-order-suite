class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :name
      t.string :email, null: false
      t.string :password_digest, null: false  # Required by has_secure_password
      t.string :role, default: "staff"        # "staff", "admin", "super_admin"
      t.references :restaurant, foreign_key: true, null: true
      t.timestamps
    end
  end
end
