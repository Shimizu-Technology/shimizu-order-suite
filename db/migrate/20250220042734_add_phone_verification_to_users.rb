# db/migrate/20250301000000_add_phone_verification_to_users.rb
class AddPhoneVerificationToUsers < ActiveRecord::Migration[7.2]
  def change
    # Add three columns:
    # 1) phone_verified (boolean)
    # 2) verification_code (string)
    # 3) verification_code_sent_at (datetime)
    add_column :users, :phone_verified, :boolean, default: false
    add_column :users, :verification_code, :string
    add_column :users, :verification_code_sent_at, :datetime
  end
end
