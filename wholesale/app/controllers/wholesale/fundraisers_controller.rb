# app/controllers/wholesale/fundraisers_controller.rb

module Wholesale
  class FundraisersController < ApplicationController
    # Skip authentication for public browsing of fundraisers
    skip_before_action :authorize_request, only: [:index, :show]
    before_action :find_fundraiser_by_slug, only: [:show]
    
    # GET /wholesale/fundraisers
    # List all active fundraisers for the current restaurant
    def index
      @fundraisers = Wholesale::Fundraiser
        .where(restaurant: current_restaurant)
        .active
        .current
        .includes(:participants)
        .order(:name)
      
      render_success(
        fundraisers: @fundraisers.map { |fundraiser| fundraiser_summary(fundraiser) },
        message: "Active fundraisers retrieved successfully"
      )
    end
    
    # GET /wholesale/fundraisers/:slug
    # Get detailed information about a specific fundraiser
    def show
      return unless @fundraiser
      
      # Include items and participants for the detailed view
      @fundraiser = Wholesale::Fundraiser
        .where(restaurant: current_restaurant)
        .active
        .current
        .includes(
          items: [:item_images],
          participants: []
        )
        .find_by!(slug: params[:slug])
      
      render_success(
        fundraiser: fundraiser_detail(@fundraiser),
        message: "Fundraiser details retrieved successfully"
      )
    rescue ActiveRecord::RecordNotFound
      render_not_found("Fundraiser not found")
    end
    
    private
    
    # Summary format for item listing (shared with ItemsController)
    def item_summary(item)
      {
        id: item.id,
        name: item.name,
        description: item.description,
        sku: item.sku,
        price: item.price,
        price_cents: item.price_cents,
        position: item.position,
        sort_order: item.sort_order,
        options: item.options,
        
        # Availability
        active: item.active?,
        track_inventory: item.track_inventory?,
        in_stock: item.in_stock?,
        stock_status: item.stock_status,
        available_quantity: item.track_inventory? ? item.available_quantity : nil,
        
        # Primary image and all images for carousel
        primary_image_url: item.primary_image_url,
        images: item.item_images.order(:position).map do |img|
          {
            id: img.id,
            image_url: img.image_url,
            alt_text: img.alt_text,
            position: img.position,
            primary: img.primary
          }
        end,
        
        # Basic statistics
        total_ordered: item.total_ordered_quantity,
        
        # Option Groups (new system)
        option_groups: item.option_groups.includes(:options).order(:position).map do |group|
          {
            id: group.id,
            name: group.name,
            min_select: group.min_select,
            max_select: group.max_select,
            required: group.required,
            position: group.position,
            options: group.options.order(:position).map do |option|
              {
                id: option.id,
                name: option.name,
                additional_price: option.additional_price.to_f,
                available: option.available,
                position: option.position
              }
            end
          }
        end,
        
        created_at: item.created_at,
        updated_at: item.updated_at
      }
    end
    
    # Summary format for fundraiser listing
    def fundraiser_summary(fundraiser)
      {
        id: fundraiser.id,
        name: fundraiser.name,
        slug: fundraiser.slug,
        description: fundraiser.description,
        start_date: fundraiser.start_date,
        end_date: fundraiser.end_date,
        contact_email: fundraiser.contact_email,
        contact_phone: fundraiser.contact_phone,
        status: fundraiser.status,
        
        # Pickup information for customers
        pickup_display_name: fundraiser.pickup_display_name,
        pickup_display_address: fundraiser.pickup_display_address,
        pickup_instructions: fundraiser.pickup_instructions,
        pickup_contact_name: fundraiser.pickup_contact_name,
        pickup_contact_phone: fundraiser.pickup_contact_display_phone,
        pickup_hours: fundraiser.pickup_hours,
        participant_count: fundraiser.participants.active.count,
        item_count: fundraiser.items.active.count,
        total_orders: fundraiser.total_orders_count,
        total_revenue: fundraiser.total_revenue_cents / 100.0,
        
        # Image URLs
        card_image_url: fundraiser.card_image_url,
        banner_url: fundraiser.banner_url,
        has_card_image: fundraiser.has_card_image?,
        has_banner_image: fundraiser.has_banner_image?,
        
        url: "/wholesale/#{fundraiser.slug}",
        created_at: fundraiser.created_at,
        updated_at: fundraiser.updated_at
      }
    end
    
    # Detailed format for specific fundraiser view
    def fundraiser_detail(fundraiser)
      {
        id: fundraiser.id,
        name: fundraiser.name,
        slug: fundraiser.slug,
        description: fundraiser.description,
        start_date: fundraiser.start_date,
        end_date: fundraiser.end_date,
        contact_email: fundraiser.contact_email,
        contact_phone: fundraiser.contact_phone,
        terms_and_conditions: fundraiser.terms_and_conditions,
        status: fundraiser.status,
        settings: fundraiser.settings,
        total_orders: fundraiser.total_orders_count,
        total_revenue: fundraiser.total_revenue_cents / 100.0,
        
        # Pickup information for customers
        pickup_display_name: fundraiser.pickup_display_name,
        pickup_display_address: fundraiser.pickup_display_address,
        pickup_instructions: fundraiser.pickup_instructions,
        pickup_contact_name: fundraiser.pickup_contact_name,
        pickup_contact_phone: fundraiser.pickup_contact_display_phone,
        pickup_hours: fundraiser.pickup_hours,
        
        # Image URLs
        card_image_url: fundraiser.card_image_url,
        banner_url: fundraiser.banner_url,
        has_card_image: fundraiser.has_card_image?,
        has_banner_image: fundraiser.has_banner_image?,
        
        url: "/wholesale/#{fundraiser.slug}",
        
        # Items available for purchase (using item_summary for consistency with option groups)
        items: fundraiser.items.active.includes(:item_images, option_groups: :options).by_sort_order.map do |item|
          item_summary(item)
        end,
        
        # Participants for attribution
        participants: fundraiser.participants.active.by_name.map do |participant|
          {
            id: participant.id,
            name: participant.name,
            slug: participant.slug,
            description: participant.description,
            photo_url: participant.photo_url,
            
            # Goal tracking
            has_goal: participant.has_goal?,
            goal_amount: participant.goal_amount,
            current_amount: participant.current_amount,
            goal_progress_percentage: participant.goal_progress_percentage,
            goal_remaining: participant.goal_remaining,
            goal_status: participant.goal_status,
            
            # Statistics
            total_orders: participant.total_orders_count,
            total_raised: participant.total_raised,
            
            url: "/wholesale/#{fundraiser.slug}?participant=#{participant.slug}",
            created_at: participant.created_at,
            updated_at: participant.updated_at
          }
        end,
        
        created_at: fundraiser.created_at,
        updated_at: fundraiser.updated_at
      }
    end
  end
end