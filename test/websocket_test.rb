#!/usr/bin/env ruby
# test/websocket_test.rb
# 
# A simple test script to verify WebSocket functionality in the Shimizu Order Suite application
# Run this script with: ruby test/websocket_test.rb

require 'websocket-client-simple'
require 'json'
require 'jwt'
require 'optparse'
require 'logger'

# Setup logger
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
end

# Parse command line options
options = {
  host: 'localhost',
  port: 3000,
  channel: 'order',
  restaurant_id: 1,
  user_id: 1,
  jwt_secret: nil,
  jwt_algorithm: 'HS256',
  jwt_expiration: 1.hour.to_i
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby test/websocket_test.rb [options]"

  opts.on("-h", "--host HOST", "WebSocket host (default: localhost)") do |h|
    options[:host] = h
  end

  opts.on("-p", "--port PORT", "WebSocket port (default: 3000)") do |p|
    options[:port] = p.to_i
  end

  opts.on("-c", "--channel CHANNEL", "Channel to test (order, inventory, menu, notification, category)") do |c|
    options[:channel] = c
  end

  opts.on("-r", "--restaurant-id ID", "Restaurant ID") do |r|
    options[:restaurant_id] = r.to_i
  end

  opts.on("-u", "--user-id ID", "User ID") do |u|
    options[:user_id] = u.to_i
  end

  opts.on("-s", "--jwt-secret SECRET", "JWT secret key") do |s|
    options[:jwt_secret] = s
  end

  opts.on("-a", "--jwt-algorithm ALGORITHM", "JWT algorithm (default: HS256)") do |a|
    options[:jwt_algorithm] = a
  end

  opts.on("-e", "--jwt-expiration SECONDS", "JWT expiration in seconds (default: 3600)") do |e|
    options[:jwt_expiration] = e.to_i
  end

  opts.on("--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Get JWT secret from environment if not provided
if options[:jwt_secret].nil?
  # Try to read from Rails credentials
  begin
    require File.expand_path('../../config/environment', __FILE__)
    options[:jwt_secret] = Rails.application.credentials.secret_key_base
    logger.info "Using JWT secret from Rails credentials"
  rescue => e
    logger.error "Failed to load Rails environment: #{e.message}"
    logger.error "Please provide a JWT secret using the -s option"
    exit 1
  end
end

# Generate JWT token
def generate_jwt(user_id, restaurant_id, secret, algorithm, expiration)
  payload = {
    user_id: user_id,
    restaurant_id: restaurant_id,
    exp: Time.now.to_i + expiration
  }
  
  JWT.encode(payload, secret, algorithm)
end

token = generate_jwt(
  options[:user_id], 
  options[:restaurant_id], 
  options[:jwt_secret], 
  options[:jwt_algorithm], 
  options[:jwt_expiration]
)

# Determine WebSocket URL and channel name
ws_url = "ws://#{options[:host]}:#{options[:port]}/cable"
channel_name = "#{options[:channel]}_channel_#{options[:restaurant_id]}"

logger.info "Connecting to WebSocket server at #{ws_url}"
logger.info "Testing channel: #{channel_name}"
logger.info "Using JWT token: #{token}"

# Connect to WebSocket
ws = WebSocket::Client::Simple.connect(ws_url, {
  headers: {
    'Authorization' => "Bearer #{token}"
  }
})

# Track connection state
connected = false
subscribed = false

ws.on :open do
  logger.info "WebSocket connection established"
  connected = true
  
  # Send subscription message
  subscription_message = {
    command: 'subscribe',
    identifier: JSON.generate({
      channel: "#{options[:channel].capitalize}Channel",
      restaurant_id: options[:restaurant_id]
    })
  }
  
  logger.info "Sending subscription request: #{subscription_message.to_json}"
  ws.send(subscription_message.to_json)
end

ws.on :message do |msg|
  begin
    data = JSON.parse(msg.data)
    logger.debug "Received message: #{data}"
    
    # Handle welcome message
    if data['type'] == 'welcome'
      logger.info "Received welcome message from server"
    end
    
    # Handle successful subscription
    if data['type'] == 'confirm_subscription'
      logger.info "Successfully subscribed to channel"
      subscribed = true
    end
    
    # Handle ping message
    if data['type'] == 'ping'
      logger.debug "Received ping from server"
    end
    
    # Handle actual channel messages
    if data['message'] && !data['message'].empty?
      logger.info "Received channel message: #{data['message']}"
    end
  rescue JSON::ParserError => e
    logger.error "Failed to parse message: #{e.message}"
    logger.error "Raw message: #{msg.data}"
  end
end

ws.on :error do |e|
  logger.error "WebSocket error: #{e.message}"
end

ws.on :close do |e|
  logger.info "WebSocket connection closed: #{e.inspect}"
  exit 1 if !connected
end

# Keep the script running
begin
  # Wait for connection and subscription
  30.times do
    break if subscribed
    sleep 0.5
    logger.debug "Waiting for subscription confirmation..."
  end
  
  if subscribed
    logger.info "Connection and subscription successful!"
    logger.info "Listening for messages. Press Ctrl+C to exit."
    
    # Keep the connection alive
    loop do
      sleep 1
    end
  else
    logger.error "Failed to subscribe to channel within timeout"
    exit 1
  end
rescue Interrupt
  logger.info "Closing connection..."
  ws.close
  exit 0
end
