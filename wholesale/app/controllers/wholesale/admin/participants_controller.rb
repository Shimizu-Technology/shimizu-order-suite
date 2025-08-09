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
          participant.attributes.merge(
            'fundraiser_name' => participant.fundraiser&.name,
            'total_orders' => 0, # TODO: Calculate from orders
            'total_items_sold' => 0 # TODO: Calculate from orders
          )
        end
        
        render_success(participants: participants_with_stats)
      end
      
      # GET /wholesale/admin/participants/:id
      def show
        participant_data = @participant.attributes.merge(
          'fundraiser_name' => @participant.fundraiser&.name,
          'total_orders' => 0, # TODO: Calculate from orders
          'total_items_sold' => 0 # TODO: Calculate from orders
        )
        
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