# app/services/reservation_service.rb
class ReservationService < TenantScopedService
  attr_accessor :current_user

  # List all reservations for the current restaurant
  def list_reservations(params = {})
    reservations = scope_query(Reservation)
    
    # Apply filters if provided
    if params[:status].present?
      reservations = reservations.where(status: params[:status])
    end
    
    if params[:date].present?
      date = Date.parse(params[:date])
      reservations = reservations.where(
        "reservation_date >= ? AND reservation_date < ?", 
        date.beginning_of_day, 
        date.end_of_day
      )
    end
    
    if params[:customer_name].present?
      reservations = reservations.where(
        "customer_name ILIKE ?", 
        "%#{params[:customer_name]}%"
      )
    end
    
    if params[:phone].present?
      reservations = reservations.where(
        "phone ILIKE ?", 
        "%#{params[:phone]}%"
      )
    end
    
    if params[:email].present?
      reservations = reservations.where(
        "email ILIKE ?", 
        "%#{params[:email]}%"
      )
    end
    
    # Order by date and time
    reservations = reservations.order(reservation_date: :asc)
    
    # Paginate if requested
    if params[:page].present? && params[:per_page].present?
      page = params[:page].to_i
      per_page = params[:per_page].to_i
      reservations = reservations.page(page).per(per_page)
    end
    
    { success: true, reservations: reservations }
  rescue => e
    { success: false, errors: ["Failed to list reservations: #{e.message}"], status: :internal_server_error }
  end

  # Find a specific reservation
  def find_reservation(id)
    reservation = scope_query(Reservation).find_by(id: id)
    
    if reservation
      { success: true, reservation: reservation }
    else
      { success: false, errors: ["Reservation not found"], status: :not_found }
    end
  rescue => e
    { success: false, errors: ["Failed to find reservation: #{e.message}"], status: :internal_server_error }
  end

  # Create a new reservation
  def create_reservation(params)
    reservation = Reservation.new(params)
    reservation.restaurant = current_restaurant
    
    if reservation.save
      { success: true, reservation: reservation }
    else
      { success: false, errors: reservation.errors.full_messages, status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to create reservation: #{e.message}"], status: :internal_server_error }
  end

  # Update an existing reservation
  def update_reservation(id, params)
    reservation = scope_query(Reservation).find_by(id: id)
    
    unless reservation
      return { success: false, errors: ["Reservation not found"], status: :not_found }
    end
    
    if reservation.update(params)
      { success: true, reservation: reservation }
    else
      { success: false, errors: reservation.errors.full_messages, status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to update reservation: #{e.message}"], status: :internal_server_error }
  end

  # Delete a reservation
  def delete_reservation(id)
    reservation = scope_query(Reservation).find_by(id: id)
    
    unless reservation
      return { success: false, errors: ["Reservation not found"], status: :not_found }
    end
    
    if reservation.destroy
      { success: true }
    else
      { success: false, errors: ["Failed to delete reservation"], status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to delete reservation: #{e.message}"], status: :internal_server_error }
  end

  # Change the status of a reservation
  def change_reservation_status(id, status)
    reservation = scope_query(Reservation).find_by(id: id)
    
    unless reservation
      return { success: false, errors: ["Reservation not found"], status: :not_found }
    end
    
    if reservation.update(status: status)
      { success: true, reservation: reservation }
    else
      { success: false, errors: reservation.errors.full_messages, status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to change reservation status: #{e.message}"], status: :internal_server_error }
  end

  # Check availability for a given date, time, and party size
  def check_availability(date, time, party_size)
    # This would include logic to check table availability
    # based on existing reservations and restaurant capacity
    
    # For now, we'll return a simple response
    { success: true, available: true }
  rescue => e
    { success: false, errors: ["Failed to check availability: #{e.message}"], status: :internal_server_error }
  end
end
