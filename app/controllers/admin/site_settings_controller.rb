# app/controllers/admin/site_settings_controller.rb
module Admin
  class SiteSettingsController < ApplicationController
    before_action :authorize_request, except: [:show]
    before_action :require_admin!, except: [:show]
    
    # Mark all actions as public endpoints that don't require restaurant context
    def public_endpoint?
      true
    end

    # GET /admin/site_settings
    def show
      settings = SiteSetting.first_or_create!
      render json: settings
    end

    # PATCH /admin/site_settings
    # Accepts optional file fields: hero_image, spinner_image
    def update
      settings = SiteSetting.first_or_create!

      if params[:hero_image].present?
        file = params[:hero_image]
        ext = File.extname(file.original_filename)
        new_filename = "hero_#{Time.now.to_i}#{ext}"
        public_url   = S3Uploader.upload(file, new_filename)
        settings.hero_image_url = public_url
      end

      if params[:spinner_image].present?
        file = params[:spinner_image]
        ext = File.extname(file.original_filename)
        new_filename = "spinner_#{Time.now.to_i}#{ext}"
        public_url   = S3Uploader.upload(file, new_filename)
        settings.spinner_image_url = public_url
      end

      # If you have textual fields, you can handle them here too
      # e.g. settings.welcome_text = params[:welcome_text] if params[:welcome_text].present?

      settings.save!
      render json: settings
    end

    private

    def require_admin!
      unless current_user&.role.in?(%w[admin super_admin])
        render json: { error: "Forbidden" }, status: :forbidden
      end
    end
  end
end
