module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :restaurant_id

    def connect
      Rails.logger.info("WebSocket connection attempt - Request details: " + {
        remote_addr: request.remote_addr,
        user_agent: request.env['HTTP_USER_AGENT'],
        origin: request.origin,
        params: request.params.except(:token).to_json,
        headers: request.headers.to_h.select { |k, _| k.start_with?('HTTP_') },
        protocol: request.env['rack.url_scheme'],
        env: Rails.env,
        time: Time.current.iso8601
      }.to_json)

      Rails.logger.debug("WebSocket connection - Starting authentication")

      self.current_user = find_verified_user
      self.restaurant_id = current_user&.restaurant_id

      if current_user && restaurant_id
        Rails.logger.info("WebSocket connection established - " + {
          user_id: current_user.id,
          restaurant_id: restaurant_id,
          email: current_user.email,
          connection_id: connection_identifier,
          role: current_user.role,
          subscriptions: [],  # Will be populated as channels are subscribed
          connected_at: Time.current.iso8601,
          server_id: Process.pid
        }.to_json)

        # Monitor connection state - only if we're in a server that supports timers
        if defined?(ActionCable.server.pubsub.send(:broadcast_adapter).connection.server.reactor) && ActionCable.server.pubsub.send(:broadcast_adapter).connection.server.reactor.running?
          @monitoring_timer = ActionCable.server.pubsub.send(:broadcast_adapter).connection.server.reactor.add_periodic_timer(30) do
            if connected?
              Rails.logger.debug("WebSocket connection health check - " + {
                connection_id: connection_identifier,
                user_id: current_user.id,
                uptime: Time.current - @connected_at,
                subscriptions: subscriptions.keys
              }.to_json)
            end
          end
        end
      else
        error_details = {
          has_user: current_user.present?,
          has_restaurant: restaurant_id.present?,
          connection_id: connection_identifier,
          time: Time.current.iso8601
        }
        Rails.logger.error("WebSocket connection failed - Missing user or restaurant_id - " + error_details.to_json)
        reject_unauthorized_connection
      end
    end

    def disconnect
      uptime = @connected_at ? (Time.current - @connected_at) : nil
      
      Rails.logger.info("WebSocket connection disconnected - " + {
        user_id: current_user&.id,
        restaurant_id: restaurant_id,
        connection_id: connection_identifier,
        uptime: uptime,
        reason: 'Client disconnected'
      }.to_json)

      if @monitoring_timer && defined?(ActionCable.server.pubsub.send(:broadcast_adapter).connection.server.reactor)
        ActionCable.server.pubsub.send(:broadcast_adapter).connection.server.reactor.cancel_timer(@monitoring_timer)
      end
      @monitoring_timer = nil
      # No call to super as there's no disconnect method in the parent class
    end

    private

    def find_verified_user
      token = request.params[:token]
      unless token
        Rails.logger.error("WebSocket authentication failed - No token provided")
        return reject_unauthorized_connection
      end
      
      # Log token information for debugging (without revealing the actual token)
      Rails.logger.debug("WebSocket authentication - Token received with length: #{token.length}, first 3 chars: #{token[0..2]}")

      Rails.logger.debug("WebSocket authentication - Starting token verification")
      
      begin
        decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')[0]
        user_id = decoded["user_id"]
        
        Rails.logger.debug("WebSocket authentication - Token decoded successfully - " + {
          user_id: user_id,
          exp: decoded["exp"],
          iat: decoded["iat"]
        }.to_json)
        
        user = User.find_by(id: user_id)
        
        if decoded["exp"].present?
          expiration_time = Time.at(decoded["exp"])
          time_until_expiry = expiration_time - Time.current
          
          if time_until_expiry < 0
            Rails.logger.error("WebSocket authentication failed - Token expired - " + {
              user_id: user_id,
              expired_at: expiration_time,
              expired_ago: -time_until_expiry
            }.to_json)
            return reject_unauthorized_connection
          end
          
          Rails.logger.debug("WebSocket authentication - Token expiration valid - " + {
            expires_in: time_until_expiry,
            expires_at: expiration_time
          }.to_json)
        end
        
        if user
          Rails.logger.info("WebSocket authentication successful - " + {
            user_id: user.id,
            email: user.email,
            restaurant_id: user.restaurant_id,
            role: user.role
          }.to_json)
          user
        else
          Rails.logger.error("WebSocket authentication failed - User not found - " + {
            user_id: user_id
          }.to_json)
          reject_unauthorized_connection
        end
      rescue JWT::DecodeError => e
        Rails.logger.error("WebSocket authentication failed - JWT decode error - " + {
          error: e.message,
          token_preview: token[0..10]
        }.to_json)
        reject_unauthorized_connection
      rescue => e
        Rails.logger.error("WebSocket authentication failed - Unexpected error - " + {
          error_class: e.class.name,
          error_message: e.message,
          backtrace: e.backtrace&.first(5)
        }.to_json)
        reject_unauthorized_connection
      end
    end
  end
end
