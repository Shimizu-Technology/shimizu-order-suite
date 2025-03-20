class WebhookEndpointsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_webhook_endpoint, only: [:show, :update, :destroy]
  
  def index
    @webhook_endpoints = WebhookEndpoint.where(restaurant_id: params[:restaurant_id])
    render json: @webhook_endpoints
  end
  
  def show
    render json: @webhook_endpoint
  end
  
  def create
    @webhook_endpoint = WebhookEndpoint.new(webhook_endpoint_params)
    
    # Generate a secret if not provided
    @webhook_endpoint.secret ||= SecureRandom.hex(32)
    
    if @webhook_endpoint.save
      render json: @webhook_endpoint, status: :created
    else
      render json: { errors: @webhook_endpoint.errors }, status: :unprocessable_entity
    end
  end
  
  def update
    if @webhook_endpoint.update(webhook_endpoint_params)
      render json: @webhook_endpoint
    else
      render json: { errors: @webhook_endpoint.errors }, status: :unprocessable_entity
    end
  end
  
  def destroy
    @webhook_endpoint.destroy
    head :no_content
  end
  
  private
  
  def set_webhook_endpoint
    @webhook_endpoint = WebhookEndpoint.find(params[:id])
  end
  
  def webhook_endpoint_params
    params.require(:webhook_endpoint).permit(
      :url, :description, :active, :restaurant_id, event_types: []
    )
  end
  
  def authorize_admin!
    unless current_user.role == 'admin' || current_user.role == 'super_admin'
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
end
