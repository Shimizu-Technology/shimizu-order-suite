# app/controllers/api/wholesale/fundraiser_participants_controller.rb

module Api
  module Wholesale
    class FundraiserParticipantsController < Api::Wholesale::ApiController
      include TenantIsolation
      
      before_action :authorize_request, except: [:index, :show]
      before_action :optional_authorize, only: [:index, :show]
      before_action :ensure_tenant_context
      before_action :set_fundraiser
      before_action :set_fundraiser_participant, only: [:show, :update, :destroy]
      
      # GET /api/wholesale/fundraisers/:fundraiser_id/participants
      def index
        authorize @fundraiser, :show?
        @participants = policy_scope(FundraiserParticipant).where(fundraiser_id: @fundraiser.id)
        
        # Apply filters if provided
        @participants = @participants.where(active: true) if params[:active].present? && params[:active] == 'true'
        @participants = @participants.by_team(params[:team]) if params[:team].present?
        
        # Apply sorting
        sort_by = params[:sort_by] || 'name'
        sort_direction = params[:sort_direction] || 'asc'
        @participants = @participants.order("#{sort_by} #{sort_direction}")
        
        # Apply pagination
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 25).to_i
        @participants = @participants.page(page).per(per_page)
        
        render json: {
          participants: @participants,
          meta: {
            total_count: @participants.total_count,
            total_pages: @participants.total_pages,
            current_page: @participants.current_page,
            per_page: per_page
          }
        }
      end
      
      # GET /api/wholesale/fundraisers/:fundraiser_id/participants/:id
      def show
        authorize @participant
        render json: @participant
      end
      
      # POST /api/wholesale/fundraisers/:fundraiser_id/participants
      def create
        authorize @fundraiser, :update?
        @participant = @fundraiser.fundraiser_participants.new(participant_params)
        
        if @participant.save
          render json: @participant, status: :created
        else
          render json: { errors: @participant.errors }, status: :unprocessable_entity
        end
      end
      
      # PATCH/PUT /api/wholesale/fundraisers/:fundraiser_id/participants/:id
      def update
        authorize @participant
        if @participant.update(participant_params)
          render json: @participant
        else
          render json: { errors: @participant.errors }, status: :unprocessable_entity
        end
      end
      
      # DELETE /api/wholesale/fundraisers/:fundraiser_id/participants/:id
      def destroy
        authorize @participant
        @participant.destroy
        head :no_content
      end
      
      # POST /api/wholesale/fundraisers/:fundraiser_id/participants/bulk_import
      def bulk_import
        authorize @fundraiser, :update?
        
        if params[:file].present?
          result = import_from_file
        elsif params[:participants].present?
          result = import_from_params
        else
          result = { success: false, message: "No data provided for import" }
        end
        
        if result[:success]
          render json: { message: result[:message], imported_count: result[:imported_count] }
        else
          render json: { error: result[:message] }, status: :unprocessable_entity
        end
      end
      
      private
      
      def set_fundraiser
        @fundraiser = current_restaurant.fundraisers.find(params[:fundraiser_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Fundraiser not found' }, status: :not_found
      end
      
      def set_fundraiser_participant
        @participant = @fundraiser.fundraiser_participants.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Participant not found' }, status: :not_found
      end
      
      def participant_params
        params.require(:participant).permit(:name, :team, :active)
      end
      
      def import_from_file
        require 'csv'
        
        begin
          file = params[:file]
          participants_data = []
          
          CSV.foreach(file.path, headers: true) do |row|
            participants_data << {
              name: row['name'],
              team: row['team'],
              active: row['active'].to_s.downcase == 'true'
            }
          end
          
          import_participants(participants_data)
        rescue => e
          { success: false, message: "Error processing CSV file: #{e.message}" }
        end
      end
      
      def import_from_params
        begin
          participants_data = params[:participants].map do |p|
            {
              name: p[:name],
              team: p[:team],
              active: p[:active]
            }
          end
          
          import_participants(participants_data)
        rescue => e
          { success: false, message: "Error processing participants data: #{e.message}" }
        end
      end
      
      def import_participants(participants_data)
        imported_count = 0
        errors = []
        
        ActiveRecord::Base.transaction do
          participants_data.each do |data|
            participant = @fundraiser.fundraiser_participants.new(data)
            
            if participant.save
              imported_count += 1
            else
              errors << { data: data, errors: participant.errors.full_messages }
            end
          end
          
          # If there are any errors, rollback the transaction
          raise ActiveRecord::Rollback if errors.any?
        end
        
        if errors.any?
          { success: false, message: "Some participants could not be imported", errors: errors }
        else
          { success: true, message: "Successfully imported #{imported_count} participants", imported_count: imported_count }
        end
      end
    end
  end
end
