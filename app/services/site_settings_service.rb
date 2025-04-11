# app/services/site_settings_service.rb
class SiteSettingsService < TenantScopedService
  # Get site settings for the current restaurant
  def get_settings
    # Get restaurant-specific site settings or create if not exists
    settings = scope_query(SiteSetting).first_or_initialize
    
    # If this is a new record, ensure it's associated with the current restaurant
    if settings.new_record?
      settings.restaurant = restaurant
      settings.save!
    end
    
    settings
  end

  # Update site settings for the current restaurant
  def update_settings(params)
    settings = scope_query(SiteSetting).first_or_create!

    if params[:hero_image].present?
      file = params[:hero_image]
      ext = File.extname(file.original_filename)
      new_filename = "hero_#{current_restaurant.id}_#{Time.now.to_i}#{ext}"
      public_url   = S3Uploader.upload(file, new_filename)
      settings.hero_image_url = public_url
    end

    if params[:spinner_image].present?
      file = params[:spinner_image]
      ext = File.extname(file.original_filename)
      new_filename = "spinner_#{current_restaurant.id}_#{Time.now.to_i}#{ext}"
      public_url   = S3Uploader.upload(file, new_filename)
      settings.spinner_image_url = public_url
    end

    # If you have textual fields, you can handle them here too
    # e.g. settings.welcome_text = params[:welcome_text] if params[:welcome_text].present?

    if settings.save
      { success: true, settings: settings }
    else
      { success: false, errors: settings.errors.full_messages, status: :unprocessable_entity }
    end
  end
end
