# app/controllers/wholesale/cart_controller.rb

module Wholesale
  class CartController < ApplicationController
    # Cart operations require authentication for user persistence
    before_action :load_cart
    before_action :find_item, only: [:add, :update]
    
    # GET /wholesale/cart
    # Get current cart contents
    def show
      render_success(
        cart: cart_summary(@cart),
        message: "Cart retrieved successfully"
      )
    end
    
    # POST /wholesale/cart/add
    # Add item to cart
    def add
      return unless @item
      
      quantity = params[:quantity].to_i
      
      if quantity <= 0
        return render_error("Quantity must be greater than 0")
      end
      
      # Check if item is available
      unless @item.can_purchase?(quantity)
        available = @item.track_inventory? ? @item.available_quantity : "unlimited"
        return render_error("Insufficient stock. Available: #{available}")
      end
      
      # Check if cart is empty or from same fundraiser
      if @cart.any? && @cart.first[:fundraiser_id] != @item.fundraiser_id
        current_fundraiser = Wholesale::Fundraiser.find(@cart.first[:fundraiser_id])
        return render_error(
          "You can only order from one fundraiser at a time. Please clear your cart or complete your current order from #{current_fundraiser.name}.",
          status: :conflict
        )
      end
      
      # Get selected options for variants
      selected_options = params[:selected_options] || {}
      
      # Check if item with same options already exists in cart  
      existing_item = @cart.find { |cart_item| 
        cart_item[:item_id] == @item.id && 
        cart_item[:selected_options] == selected_options.to_h
      }
      
      if existing_item
        # Update quantity
        new_quantity = existing_item[:quantity] + quantity
        
        unless @item.can_purchase?(new_quantity)
          available = @item.track_inventory? ? @item.available_quantity : "unlimited"
          return render_error("Total quantity exceeds availability. Available: #{available}")
        end
        
        existing_item[:quantity] = new_quantity
        existing_item[:line_total_cents] = new_quantity * @item.price_cents
        existing_item[:updated_at] = Time.current
      else
        # Add new item
        @cart << {
          item_id: @item.id,
          fundraiser_id: @item.fundraiser_id,
          name: @item.name,
          description: @item.description,
          sku: @item.sku,
          price_cents: @item.price_cents,
          quantity: quantity,
          line_total_cents: quantity * @item.price_cents,
          image_url: @item.primary_image_url,
          selected_options: selected_options.to_h,
          added_at: Time.current,
          updated_at: Time.current
        }
      end
      
      save_cart(@cart)
      
      render_success(
        cart: cart_summary(@cart),
        message: "Item added to cart successfully"
      )
    end
    
    # PUT /wholesale/cart/update
    # Update item quantity in cart
    def update
      return unless @item
      
      quantity = params[:quantity].to_i
      
      if quantity < 0
        return render_error("Quantity cannot be negative")
      end
      
      cart_item = @cart.find { |item| item[:item_id] == @item.id }
      
      unless cart_item
        return render_error("Item not found in cart")
      end
      
      if quantity == 0
        # Remove item from cart
        @cart.reject! { |item| item[:item_id] == @item.id }
        message = "Item removed from cart"
      else
        # Check availability
        unless @item.can_purchase?(quantity)
          available = @item.track_inventory? ? @item.available_quantity : "unlimited"
          return render_error("Insufficient stock. Available: #{available}")
        end
        
        # Update quantity
        cart_item[:quantity] = quantity
        cart_item[:line_total_cents] = quantity * @item.price_cents
        cart_item[:updated_at] = Time.current
        message = "Cart updated successfully"
      end
      
      save_cart(@cart)
      
      render_success(
        cart: cart_summary(@cart),
        message: message
      )
    end
    
    # DELETE /wholesale/cart/remove/:item_id
    # Remove specific item from cart
    def remove
      item_id = params[:item_id].to_i
      
      cart_item = @cart.find { |item| item[:item_id] == item_id }
      
      unless cart_item
        return render_error("Item not found in cart")
      end
      
      @cart.reject! { |item| item[:item_id] == item_id }
      save_cart(@cart)
      
      render_success(
        cart: cart_summary(@cart),
        message: "Item removed from cart successfully"
      )
    end
    
    # DELETE /wholesale/cart/clear
    # Clear entire cart
    def clear
      clear_cart
      
      render_success(
        cart: cart_summary([]),
        message: "Cart cleared successfully"
      )
    end
    
    # GET /wholesale/cart/validate
    # Validate cart items (check availability, prices, etc.)
    def validate
      return render_success(cart: cart_summary([]), valid: true, message: "Empty cart is valid") if @cart.empty?
      
      issues = []
      valid_cart = []
      
      @cart.each do |cart_item|
        begin
          item = Wholesale::Item
            .joins(:fundraiser)
            .where(fundraiser: { restaurant: current_restaurant })
            .find(cart_item[:item_id])
          
          # Check if item is still active
          unless item.active?
            issues << {
              item_id: item.id,
              name: cart_item[:name],
              issue: "Item is no longer available"
            }
            next
          end
          
          # Check if fundraiser is still active and current
          unless item.fundraiser.active? && item.fundraiser.current?
            issues << {
              item_id: item.id,
              name: cart_item[:name],
              issue: "Fundraiser is no longer accepting orders"
            }
            next
          end
          
          # Check availability
          unless item.can_purchase?(cart_item[:quantity])
            available = item.track_inventory? ? item.available_quantity : "unlimited"
            issues << {
              item_id: item.id,
              name: cart_item[:name],
              issue: "Insufficient stock. Available: #{available}, in cart: #{cart_item[:quantity]}"
            }
            next
          end
          
          # Check if price has changed
          if item.price_cents != cart_item[:price_cents]
            issues << {
              item_id: item.id,
              name: cart_item[:name],
              issue: "Price has changed from $#{cart_item[:price_cents] / 100.0} to $#{item.price}"
            }
            # Update price in cart
            cart_item[:price_cents] = item.price_cents
            cart_item[:line_total_cents] = cart_item[:quantity] * item.price_cents
          end
          
          valid_cart << cart_item
          
        rescue ActiveRecord::RecordNotFound
          issues << {
            item_id: cart_item[:item_id],
            name: cart_item[:name],
            issue: "Item no longer exists"
          }
        end
      end
      
      # Update cart with valid items only
      @cart = valid_cart
      save_cart(@cart)
      
      render_success(
        cart: cart_summary(@cart),
        valid: issues.empty?,
        issues: issues,
        message: issues.empty? ? "Cart is valid" : "Cart has #{issues.length} issue(s)"
      )
    end
    
    private
    
    def load_cart
      @cart = get_cart
    end
    
    def find_item
      item_id = params[:item_id] || params[:id]
      @item = Wholesale::Item
        .joins(:fundraiser)
        .where(fundraiser: { restaurant: current_restaurant, active: true })
        .merge(Wholesale::Fundraiser.current)
        .find(item_id)
    rescue ActiveRecord::RecordNotFound
      render_not_found("Item not found")
      nil
    end
    
    def get_cart
      if current_user
        # User-based cart (stored in database or session with user ID)
        session["wholesale_cart_#{current_user.id}"] ||= []
      else
        # Session-based cart for anonymous users
        session[:wholesale_cart] ||= []
      end
    end
    
    def save_cart(cart)
      if current_user
        session["wholesale_cart_#{current_user.id}"] = cart
      else
        session[:wholesale_cart] = cart
      end
    end
    
    def clear_cart
      if current_user
        session.delete("wholesale_cart_#{current_user.id}")
      else
        session.delete(:wholesale_cart)
      end
    end
    
    def cart_summary(cart)
      return empty_cart_summary if cart.empty?
      
      # Get fundraiser info
      fundraiser_id = cart.first[:fundraiser_id]
      fundraiser = Wholesale::Fundraiser.find(fundraiser_id)
      
      total_cents = cart.sum { |item| item[:line_total_cents] }
      total_quantity = cart.sum { |item| item[:quantity] }
      
      {
        items: cart.map do |cart_item|
          {
            item_id: cart_item[:item_id],
            name: cart_item[:name],
            description: cart_item[:description],
            sku: cart_item[:sku],
            price: cart_item[:price_cents] / 100.0,
            price_cents: cart_item[:price_cents],
            quantity: cart_item[:quantity],
            line_total: cart_item[:line_total_cents] / 100.0,
            line_total_cents: cart_item[:line_total_cents],
            image_url: cart_item[:image_url],
            added_at: cart_item[:added_at],
            updated_at: cart_item[:updated_at]
          }
        end,
        
        fundraiser: {
          id: fundraiser.id,
          name: fundraiser.name,
          slug: fundraiser.slug
        },
        
        totals: {
          item_count: cart.length,
          total_quantity: total_quantity,
          subtotal: total_cents / 100.0,
          subtotal_cents: total_cents,
          # Note: Tax and shipping would be calculated at checkout
        },
        
        cart_url: "/wholesale/cart",
        checkout_url: "/wholesale/checkout"
      }
    end
    
    def empty_cart_summary
      {
        items: [],
        fundraiser: nil,
        totals: {
          item_count: 0,
          total_quantity: 0,
          subtotal: 0.0,
          subtotal_cents: 0
        },
        cart_url: "/wholesale/cart",
        checkout_url: "/wholesale/checkout"
      }
    end
  end
end