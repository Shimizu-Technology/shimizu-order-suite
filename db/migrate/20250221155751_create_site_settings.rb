# db/migrate/20250221155751_create_site_settings.rb

class CreateSiteSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :site_settings do |t|
      t.string :hero_image_url
      t.string :spinner_image_url
      t.timestamps
    end

    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO site_settings (created_at, updated_at)
          VALUES (NOW(), NOW())
        SQL
      end
    end
  end
end
