# app/controllers/wholesale/admin/participants_controller.rb

module Wholesale
  module Admin
    class ParticipantsController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_fundraiser, only: [:index, :show, :create, :update, :destroy, :toggle_active], if: :nested_route?
      before_action :set_participant, only: [:show, :update, :destroy, :toggle_active]
      before_action :set_restaurant_context
      
      # GET /wholesale/admin/participants
      # GET /wholesale/admin/fundraisers/:fundraiser_id/participants
      def index
        participants = Wholesale::Participant.joins(:fundraiser)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .includes(:fundraiser)
        
        # Apply fundraiser scoping if present
        if @fundraiser
          # Nested route: scope to specific fundraiser
          participants = participants.where(fundraiser_id: @fundraiser.id)
        elsif params[:fundraiser_id].present?
          # Parameter-based filtering for backward compatibility
          participants = participants.where(fundraiser_id: params[:fundraiser_id])
        end
        
        # Add computed fields
        participants_with_stats = participants.map do |participant|
          participant_with_computed_fields(participant)
        end
        
        # Add General Organization Support for orders without specific participants
        if @fundraiser
          # For specific fundraiser, add general support for that fundraiser
          general_support_entry = create_general_support_entry(@fundraiser.id, @fundraiser.name)
          participants_with_stats.unshift(general_support_entry) if general_support_entry
        elsif params[:fundraiser_id].present?
          # Parameter-based filtering for backward compatibility
          fundraiser = Wholesale::Fundraiser.where(restaurant: current_restaurant)
            .find_by(id: params[:fundraiser_id])
          if fundraiser
            general_support_entry = create_general_support_entry(fundraiser.id, fundraiser.name)
            participants_with_stats.unshift(general_support_entry) if general_support_entry
          end
        else
          # For global view, add general support across all fundraisers
          # Note: This might be complex for the global view, so we'll focus on fundraiser-specific for now
        end
        
        render_success(participants: participants_with_stats)
      end
      
      # GET /wholesale/admin/participants/:id
      def show
        participant_data = participant_with_computed_fields(@participant)
        render_success(participant: participant_data)
      end
      
      # POST /wholesale/admin/participants
      # POST /wholesale/admin/fundraisers/:fundraiser_id/participants
      def create
        # Use @fundraiser if set (nested route), otherwise verify from params
        fundraiser = @fundraiser
        
        if fundraiser.nil?
          # Flat route: verify fundraiser belongs to current restaurant
          fundraiser = Wholesale::Fundraiser.where(restaurant: current_restaurant)
            .find_by(id: participant_params[:fundraiser_id])
          
          unless fundraiser
            render_error('Fundraiser not found or not accessible')
            return
          end
        end
        
        # Ensure fundraiser_id is set correctly for nested routes
        create_params = participant_params.dup
        create_params[:fundraiser_id] = fundraiser.id
        
        participant = Wholesale::Participant.new(create_params)
        
        if participant.save
          render_success(participant: participant, message: 'Participant created successfully!', status: :created)
        else
          render_error('Failed to create participant', errors: participant.errors.full_messages)
        end
      end
      
      # PATCH/PUT /wholesale/admin/participants/:id
      def update
        if @participant.update(participant_params)
          render_success(participant: @participant, message: 'Participant updated successfully!')
        else
          render_error('Failed to update participant', errors: @participant.errors.full_messages)
        end
      end
      
      # DELETE /wholesale/admin/participants/:id
      def destroy
        if @participant.destroy
          render_success(message: 'Participant deleted successfully!')
        else
          render_error('Failed to delete participant', errors: @participant.errors.full_messages)
        end
      end
      
      # PATCH /wholesale/admin/participants/:id/toggle_active
      def toggle_active
        @participant.active = !@participant.active
        
        if @participant.save
          render_success(participant: @participant, message: "Participant #{@participant.active? ? 'activated' : 'deactivated'} successfully!")
        else
          render_error('Failed to toggle participant status', errors: @participant.errors.full_messages)
        end
      end
      
      private
      
      def set_participant
        query = Wholesale::Participant.joins(:fundraiser)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
        
        # Additional scoping for nested routes
        if @fundraiser
          query = query.where(fundraiser_id: @fundraiser.id)
        end
        
        @participant = query.find_by(id: params[:id])
        render_not_found('Participant not found') unless @participant
      end
      
      def participant_params
        permitted_params = params.require(:participant).permit(
          :fundraiser_id, :name, :email, :phone, :goal_amount, :goal_amount_cents, :photo_url, :active
        )
        
        # Convert goal_amount to goal_amount_cents if goal_amount is provided instead of goal_amount_cents
        if permitted_params[:goal_amount].present? && permitted_params[:goal_amount_cents].blank?
          permitted_params[:goal_amount_cents] = (permitted_params[:goal_amount].to_f * 100).round
          permitted_params.delete(:goal_amount)
        end
        
        permitted_params
      end
      
      def create_general_support_entry(fundraiser_id, fundraiser_name)
        # Calculate performance for orders without specific participants (general support)
        # Note: All orders count as revenue since orders can only be created after payment
        general_orders = Wholesale::Order
          .where(fundraiser_id: fundraiser_id, participant_id: nil)
        
        total_orders_count = general_orders.count
        total_raised = general_orders.sum(:total_cents) / 100.0
        
        # Only return entry if there are actually general support orders
        return nil if total_orders_count == 0
        
        {
          'id' => 'general_support', # Special ID to identify this as the general support entry
          'fundraiser_id' => fundraiser_id,
          'fundraiser_name' => fundraiser_name,
          'name' => 'General Organization Support',
          'slug' => 'general-organization-support',
          'description' => "Support #{fundraiser_name} overall",
          'photo_url' => nil,
          'goal_amount_cents' => nil,
          'goal_amount' => nil,
          'current_amount' => total_raised,
          'goal_progress_percentage' => nil,
          'total_orders_count' => total_orders_count,
          'total_raised' => total_raised,
          'total_orders' => total_orders_count,
          'total_items_sold' => 0,
          'active' => true,
          'created_at' => nil,
          'updated_at' => nil
        }
      end

      def participant_with_computed_fields(participant)
        # Calculate performance metrics from orders for this participant
        # Note: All orders count as revenue since orders can only be created after payment
        all_orders = participant.orders
        
        total_orders_count = all_orders.count
        total_raised = all_orders.sum(:total_cents) / 100.0
        
        # Calculate goal progress if participant has a goal
        goal_progress_percentage = nil
        goal_amount = nil
        current_amount = total_raised
        
        if participant.goal_amount_cents.present? && participant.goal_amount_cents > 0
          goal_amount = participant.goal_amount_cents / 100.0
          goal_progress_percentage = (current_amount / goal_amount * 100).round(2)
        end
        
        participant.attributes.merge(
          'fundraiser_name' => participant.fundraiser&.name,
          'goal_amount' => goal_amount,
          'current_amount' => current_amount,
          'goal_progress_percentage' => goal_progress_percentage,
          'total_orders_count' => total_orders_count,
          'total_raised' => total_raised,
          'total_orders' => total_orders_count, # Alias for backward compatibility
          'total_items_sold' => 0 # TODO: Calculate from order items if needed
        )
      end

      def set_restaurant_context
        unless current_restaurant
          render_unauthorized('Restaurant context not set.')
        end
      end

      def set_fundraiser
        @fundraiser = Wholesale::Fundraiser.where(restaurant: current_restaurant)
          .find_by(id: params[:fundraiser_id])
        render_not_found('Fundraiser not found') unless @fundraiser
      end

      def nested_route?
        params[:fundraiser_id].present?
      end
    end
  end
end