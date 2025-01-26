# app/controllers/seat_allocations_controller.rb

class SeatAllocationsController < ApplicationController
  before_action :authorize_request

  # GET /seat_allocations?date=YYYY-MM-DD
  def index
    Rails.logger.debug "[SeatAllocationsController#index] params=#{params.inspect}"

    base = SeatAllocation.includes(:seat, :reservation, :waitlist_entry)
                         .where(released_at: nil)

    if params[:date].present?
      begin
        date_filter = Date.parse(params[:date])

        # For a staff user:
        restaurant = Restaurant.find(current_user.restaurant_id)
        tz = restaurant.time_zone.presence || "Pacific/Guam"

        start_local = Time.use_zone(tz) do
          Time.zone.local(date_filter.year, date_filter.month, date_filter.day, 0, 0, 0)
        end
        end_local = start_local.end_of_day

        start_utc = start_local.utc
        end_utc   = end_local.utc

        base = base.where("start_time >= ? AND start_time < ?", start_utc, end_utc)
      rescue ArgumentError
        Rails.logger.warn "[SeatAllocationsController#index] invalid date param=#{params[:date]}"
      end
    end

    seat_allocations = base.all

    results = seat_allocations.map do |alloc|
      occupant_type = if alloc.reservation_id.present?
                        "reservation"
                      elsif alloc.waitlist_entry_id.present?
                        "waitlist"
                      end

      occupant_id         = nil
      occupant_name       = nil
      occupant_party_size = nil
      occupant_status     = nil

      if occupant_type == "reservation" && alloc.reservation
        occupant_id         = alloc.reservation.id
        occupant_name       = alloc.reservation.contact_name
        occupant_party_size = alloc.reservation.party_size
        occupant_status     = alloc.reservation.status
      elsif occupant_type == "waitlist" && alloc.waitlist_entry
        occupant_id         = alloc.waitlist_entry.id
        occupant_name       = alloc.waitlist_entry.contact_name
        occupant_party_size = alloc.waitlist_entry.party_size
        occupant_status     = alloc.waitlist_entry.status
      end

      {
        id:                  alloc.id,
        seat_id:             alloc.seat_id,
        seat_label:          alloc.seat&.label,
        occupant_type:       occupant_type,
        occupant_id:         occupant_id,
        occupant_name:       occupant_name,
        occupant_party_size: occupant_party_size,
        occupant_status:     occupant_status,
        start_time:          alloc.start_time,
        end_time:            alloc.end_time,
        released_at:         alloc.released_at
      }
    end

    render json: results
  end

  # POST /seat_allocations/multi_create
  def multi_create
    sa_params = params.require(:seat_allocation).permit(:occupant_type, :occupant_id, :start_time, :end_time, seat_ids: [])

    occupant_type = sa_params[:occupant_type]
    occupant_id   = sa_params[:occupant_id]
    seat_ids      = sa_params[:seat_ids] || []
    st = parse_time(sa_params[:start_time]) || Time.current
    en = parse_time(sa_params[:end_time])

    if occupant_type.blank? || occupant_id.blank? || seat_ids.empty?
      return render json: { error: "Must provide occupant_type, occupant_id, seat_ids" }, status: :unprocessable_entity
    end

    occupant = find_occupant(occupant_type, occupant_id)
    return unless occupant

    en ||= default_end_time(occupant, st)
    if st >= en
      return render json: { error: "start_time must be before end_time" }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      # occupant => "seated" unless it’s already finished, canceled, etc.
      occupant.update!(status: "seated") unless %w[seated finished canceled no_show removed].include?(occupant.status)

      seat_ids.each do |sid|
        seat = Seat.find_by(id: sid) or raise ActiveRecord::RecordNotFound, "Seat #{sid} not found"

        # *** Overlap check *** 
        conflict = SeatAllocation.where(seat_id: sid, released_at: nil)
                                 .where("start_time < ? AND end_time > ?", en, st).exists?
        raise StandardError, "Seat #{sid} is not free" if conflict

        SeatAllocation.create!(
          seat_id:           seat.id,
          reservation_id:    occupant.is_a?(Reservation) ? occupant.id : nil,
          waitlist_entry_id: occupant.is_a?(WaitlistEntry) ? occupant.id : nil,
          start_time:        st,
          end_time:          en,
          released_at:       nil
        )
      end
    end

    msg = "Seats allocated (seated) from #{st.strftime('%H:%M')} to #{en.strftime('%H:%M')} for occupant #{occupant.id}"
    render json: { message: msg }, status: :created

  rescue ActiveRecord::RecordNotFound, StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /seat_allocations/reserve
  def reserve
    ra_params = params.require(:seat_allocation).permit(:occupant_type, :occupant_id, :start_time, :end_time, seat_ids: [], seat_labels: [])

    occupant_type = ra_params[:occupant_type]
    occupant_id   = ra_params[:occupant_id]
    seat_ids      = ra_params[:seat_ids] || []
    seat_labels   = ra_params[:seat_labels] || []

    st = parse_time(ra_params[:start_time]) || Time.current
    en = parse_time(ra_params[:end_time])

    # Convert seat_labels -> seat_ids if seat_ids is empty
    if seat_ids.empty? && seat_labels.any?
      seat_ids = seat_labels.map {|lbl| Seat.find_by(label: lbl)&.id }.compact
    end

    if occupant_type.blank? || occupant_id.blank? || seat_ids.empty?
      return render json: { error: "Must provide occupant_type, occupant_id, and at least one seat" }, status: :unprocessable_entity
    end

    occupant = find_occupant(occupant_type, occupant_id) or return
    en ||= default_end_time(occupant, st)
    return render json: { error: "start_time must be before end_time" }, status: :unprocessable_entity if st >= en

    ActiveRecord::Base.transaction do
      # occupant => "reserved" unless it’s already seated, finished, etc.
      occupant.update!(status: "reserved") unless %w[seated finished canceled no_show removed].include?(occupant.status)

      seat_ids.each do |sid|
        seat = Seat.find_by(id: sid) or raise ActiveRecord::RecordNotFound, "Seat #{sid} not found"

        conflict = SeatAllocation.where(seat_id: sid, released_at: nil)
                                 .where("start_time < ? AND end_time > ?", en, st).exists?
        raise StandardError, "Seat #{sid} not free" if conflict

        SeatAllocation.create!(
          seat_id:           seat.id,
          reservation_id:    occupant.is_a?(Reservation) ? occupant.id : nil,
          waitlist_entry_id: occupant.is_a?(WaitlistEntry) ? occupant.id : nil,
          start_time:        st,
          end_time:          en,
          released_at:       nil
        )
      end
    end

    msg = "Seats reserved from #{st.strftime('%H:%M')} to #{en.strftime('%H:%M')}."
    render json: { message: msg }, status: :created

  rescue ActiveRecord::RecordNotFound, StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /seat_allocations/arrive
  def arrive
    Rails.logger.debug "[arrive] params=#{params.inspect}"
    occ_params = params.permit(:occupant_type, :occupant_id)

    occupant_type = occ_params[:occupant_type]
    occupant_id   = occ_params[:occupant_id]
    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" },
                    status: :unprocessable_entity
    end

    occupant = find_occupant(occupant_type, occupant_id)
    return unless occupant

    ActiveRecord::Base.transaction do
      if occupant.is_a?(Reservation)
        raise StandardError, "Not in reserved/booked" unless %w[reserved booked].include?(occupant.status)
      else
        raise StandardError, "Not in waiting/reserved" unless %w[waiting reserved].include?(occupant.status)
      end
      occupant.update!(status: "seated")
    end

    render json: { message: "Arrived => occupant is now 'seated'" }, status: :ok

  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /seat_allocations/no_show
  def no_show
    ns_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = ns_params[:occupant_type]
    occupant_id   = ns_params[:occupant_id]

    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" },
                    status: :unprocessable_entity
    end

    occupant = find_occupant(occupant_type, occupant_id)
    return unless occupant

    ActiveRecord::Base.transaction do
      occupant_allocs = active_allocations_for(occupant_type, occupant.id)
      occupant_allocs.each { |alloc| alloc.update!(released_at: Time.current) }

      occupant.update!(status: "no_show")
    end

    render json: { message: "Marked occupant as no_show; seat_allocations released" }, status: :ok
  end

  # POST /seat_allocations/cancel
  def cancel
    c_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = c_params[:occupant_type]
    occupant_id   = c_params[:occupant_id]

    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" },
                    status: :unprocessable_entity
    end

    occupant = find_occupant(occupant_type, occupant_id)
    return unless occupant

    ActiveRecord::Base.transaction do
      occupant_allocs = active_allocations_for(occupant_type, occupant.id)
      occupant_allocs.each { |alloc| alloc.update!(released_at: Time.current) }

      occupant.update!(status: "canceled")
    end

    render json: { message: "Canceled occupant & freed seats" }, status: :ok
  end

  # DELETE /seat_allocations/:id
  def destroy
    seat_allocation = SeatAllocation.find(params[:id])
    occupant = seat_allocation.reservation || seat_allocation.waitlist_entry
    occupant_type = seat_allocation.reservation_id.present? ? "reservation" : "waitlist"

    ActiveRecord::Base.transaction do
      seat_allocation.update!(released_at: Time.current)

      active_allocs = active_allocations_for(occupant_type, occupant.id)
      if active_allocs.none?
        occupant.update!(status: occupant_type == "reservation" ? "finished" : "removed")
      end
    end

    head :no_content
  end

  # POST /seat_allocations/finish
  def finish
    f_params = params.permit(:occupant_type, :occupant_id)

    occupant_type = f_params[:occupant_type]
    occupant_id   = f_params[:occupant_id]
    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" },
                    status: :unprocessable_entity
    end

    occupant = find_occupant(occupant_type, occupant_id)
    return unless occupant

    ActiveRecord::Base.transaction do
      occupant_allocs = active_allocations_for(occupant_type, occupant.id)
      occupant_allocs.each { |alloc| alloc.update!(released_at: Time.current) }

      new_status = occupant_type == "reservation" ? "finished" : "removed"
      occupant.update!(status: new_status)
    end

    render json: { message: "Occupant => #{occupant.status}; seats freed" }, status: :ok
  end

  private

  def parse_time(time_str)
    return nil unless time_str.present?
    Time.zone.parse(time_str) rescue nil
  end

  def find_occupant(occupant_type, occupant_id)
    occupant = case occupant_type
               when "reservation" then Reservation.find_by(id: occupant_id)
               when "waitlist"    then WaitlistEntry.find_by(id: occupant_id)
               else nil
               end
    render(json: { error: "Could not find occupant" }, status: :not_found) unless occupant
    occupant
  end

  def default_end_time(occupant, start_time)
    if occupant.is_a?(Reservation)
      (start_time || Time.current) + 60.minutes
    else
      (start_time || Time.current) + 45.minutes
    end
  end

  def active_allocations_for(occupant_type, occupant_id)
    if occupant_type == "reservation"
      SeatAllocation.where(reservation_id: occupant_id, released_at: nil)
    else
      SeatAllocation.where(waitlist_entry_id: occupant_id, released_at: nil)
    end
  end
end
