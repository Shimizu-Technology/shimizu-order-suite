# db/migrate/20250926001000_create_promo_codes.rb
class CreatePromoCodes < ActiveRecord::Migration[7.2]
  def change
    create_table :promo_codes do |t|
      t.string :code, null: false
      t.integer :discount_percent, null: false, default: 0
      t.datetime :valid_from, null: false, default: -> { "NOW()" }
      t.datetime :valid_until
      t.integer :max_uses
      t.integer :current_uses, default: 0
      t.timestamps
    end

    add_index :promo_codes, :code, unique: true
  end
end
