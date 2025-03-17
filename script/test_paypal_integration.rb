#!/usr/bin/env ruby
# frozen_string_literal: true

# This script tests the PayPal integration by creating a test order and capturing it
# Usage: rails runner script/test_paypal_integration.rb

require 'json'
require 'paypal-checkout-sdk'

# Load the Rails environment
require File.expand_path('../../config/environment', __FILE__)

# Helper method to print colored output
def print_status(message, status = :info)
  color_code = case status
               when :success then "\e[32m" # Green
               when :error then "\e[31m"   # Red
               when :warning then "\e[33m" # Yellow
               else "\e[36m"               # Cyan (info)
               end
  
  puts "#{color_code}#{message}\e[0m"
end

# Get the first restaurant (or a specific one if needed)
restaurant = Restaurant.first
if restaurant.nil?
  print_status("No restaurant found. Please create a restaurant first.", :error)
  exit 1
end

print_status("Testing PayPal integration for restaurant: #{restaurant.name}")

# Get the payment gateway settings
payment_gateway = restaurant.admin_settings&.dig('payment_gateway')
if payment_gateway.nil?
  print_status("Payment gateway settings not found for this restaurant.", :error)
  exit 1
end

# Check if PayPal is configured
if payment_gateway['payment_processor'] != 'paypal'
  print_status("This restaurant is not configured to use PayPal. Current processor: #{payment_gateway['payment_processor']}", :warning)
  print_status("Continuing with test anyway...")
end

# Get the PayPal credentials
client_id = payment_gateway['client_id']
client_secret = payment_gateway['client_secret']
test_mode = payment_gateway['test_mode'] != false # Default to true if not set

if client_id.blank? || client_secret.blank?
  print_status("PayPal credentials are not configured.", :error)
  print_status("Please set up the client_id and client_secret in the admin settings.", :error)
  exit 1
end

print_status("PayPal credentials found.")
print_status("Test mode: #{test_mode ? 'Enabled' : 'Disabled'}")

# Create a PayPal client
begin
  print_status("Creating PayPal client...")
  
  # Create the appropriate environment
  if test_mode
    environment = PayPal::SandboxEnvironment.new(client_id, client_secret)
    print_status("Using Sandbox environment")
  else
    environment = PayPal::LiveEnvironment.new(client_id, client_secret)
    print_status("Using Production environment")
  end
  
  client = PayPal::PayPalHttpClient.new(environment)
  print_status("PayPal client created successfully.", :success)
rescue => e
  print_status("Failed to create PayPal client: #{e.message}", :error)
  exit 1
end

# Create a test order
begin
  print_status("Creating a test order...")
  
  request = PayPalCheckoutSdk::Orders::OrdersCreateRequest.new
  request.request_body({
    intent: 'CAPTURE',
    purchase_units: [{
      amount: {
        currency_code: 'USD',
        value: '1.00'
      },
      reference_id: "test_order_#{Time.now.to_i}"
    }]
  })
  
  response = client.execute(request)
  
  order_id = response.result.id
  print_status("Test order created successfully. Order ID: #{order_id}", :success)
rescue => e
  print_status("Failed to create test order: #{e.message}", :error)
  exit 1
end

# Capture the test order
begin
  print_status("Capturing the test order...")
  
  request = PayPalCheckoutSdk::Orders::OrdersCaptureRequest.new(order_id)
  response = client.execute(request)
  
  capture_status = response.result.status
  transaction_id = response.result.purchase_units[0].payments.captures[0].id
  payment_amount = response.result.purchase_units[0].payments.captures[0].amount.value
  
  print_status("Test order captured successfully.", :success)
  print_status("Capture Status: #{capture_status}")
  print_status("Transaction ID: #{transaction_id}")
  print_status("Payment Amount: #{payment_amount}")
rescue => e
  print_status("Failed to capture test order: #{e.message}", :error)
  exit 1
end

# Test webhook verification
begin
  print_status("Testing webhook verification...")
  
  webhook_id = payment_gateway['paypal_webhook_id']
  
  if webhook_id.blank?
    print_status("PayPal webhook ID is not configured.", :warning)
    print_status("Skipping webhook verification test.")
    print_status("The webhook ID is required for verifying webhook notifications from PayPal.", :warning)
  else
    print_status("Webhook ID found: #{webhook_id}")
    print_status("This ID will be used to verify webhook notifications from PayPal.")
    print_status("PayPal uses HTTP headers along with this webhook ID to verify the authenticity of webhook notifications.")
    print_status("Webhook verification would be tested here in a real implementation.")
  end
rescue => e
  print_status("Error during webhook verification test: #{e.message}", :error)
end

print_status("PayPal integration test completed successfully!", :success)
print_status("Your PayPal integration appears to be working correctly.", :success)
print_status("Note: This test only verifies the basic functionality. For a complete test, you should also test the webhook integration.", :info)
