Wholesale::Engine.routes.draw do
  # Admin routes (protected)
  namespace :admin do
    resources :fundraisers do
      member do
        patch :toggle_active
        post :duplicate
      end
      
      # Nested fundraiser-scoped resources
      resources :items, only: [:index, :show, :create, :update, :destroy] do
        member do
          patch :toggle_active
          patch :set_primary_image
        end
        collection do
          post :bulk_update
        end
        
        # Variant management (legacy) - DEPRECATED: Use option_groups instead
        # resources :variants, only: [:index, :show, :update, :destroy], controller: 'item_variants'
        
        # Option Group management (new system)
        resources :option_groups, only: [:index, :show, :create, :update, :destroy] do
          resources :options, only: [:index, :show, :create, :update, :destroy] do
            collection do
              patch :batch_update_positions
            end
          end
        end
      end
      
      resources :participants, only: [:index, :show, :create, :update, :destroy] do
        member do
          patch :toggle_active
        end
      end
      
      resources :orders, only: [:index, :show, :update] do
        member do
          patch :update_status
          patch :update_tracking
          get :export
        end
        collection do
          get :export_all
          patch :bulk_update_status
          get :wholesale_statuses
        end
      end
      
      # Fundraiser-specific analytics
      get 'analytics', to: 'analytics#fundraiser_analytics'
    end
    
    # Flat routes (for backward compatibility)
    resources :items do
      member do
        patch :toggle_active
      end
      collection do
        post :bulk_update
      end
      
      # Variant management - DEPRECATED: Use option_groups instead
      # resources :variants, only: [:index, :show, :update, :destroy], controller: 'item_variants'
    end
    
    resources :participants do
      member do
        patch :toggle_active
      end
    end
    
    resources :orders, only: [:index, :show, :update] do
      member do
        patch :update_status
        patch :update_tracking
        get :export
      end
      collection do
        get :export_all
        patch :bulk_update_status
        get :wholesale_statuses
      end
    end
    
    # Option Group Presets management
    resources :option_group_presets do
      member do
        post :duplicate
        post :apply_to_item
      end
      
      # Nested option presets within group presets
      resources :option_presets, only: [:index, :show, :create, :update, :destroy]
    end
    
    # Global admin analytics and reporting
    get 'analytics', to: 'analytics#index'
    get 'analytics/revenue', to: 'analytics#revenue'
    get 'analytics/participants', to: 'analytics#participants'
    get 'analytics/fundraisers', to: 'analytics#fundraisers'
    
    # Inventory management
    get 'inventory', to: 'inventory#index'
    get 'inventory/audit_trail', to: 'inventory#audit_trail'
    
    # Item-level inventory management - direct routes
    get 'inventory/items/:id', to: 'inventory#show', as: :item_inventory_detail
    post 'inventory/items/:id/update_stock', to: 'inventory#update_item_stock', as: :update_item_stock
    post 'inventory/items/:id/mark_damaged', to: 'inventory#mark_damaged', as: :mark_item_damaged
    post 'inventory/items/:id/restock', to: 'inventory#restock', as: :restock_item
    post 'inventory/items/:id/enable_tracking', to: 'inventory#enable_tracking', as: :enable_item_tracking
    post 'inventory/items/:id/disable_tracking', to: 'inventory#disable_tracking', as: :disable_item_tracking
    
    # Option-level inventory management
    post 'inventory/options/:id/update_stock', to: 'inventory#update_option_stock', as: :update_option_stock
    post 'inventory/options/:id/mark_damaged', to: 'inventory#mark_option_damaged', as: :mark_option_damaged
    post 'inventory/options/:id/restock', to: 'inventory#restock_option', as: :restock_option
  end
  
  # Health check
  get '/health', to: 'application#health'
  
  # Fundraisers (public browsing)
  resources :fundraisers, only: [:index, :show], param: :slug do
    # Items within fundraisers
    resources :items, only: [:index, :show] do
      member do
        post :check_availability
      end
    end
  end
  
  # Items (alternative direct access)
  resources :items, only: [:show] do
    member do
      post :check_availability
    end
  end
  
  # Shopping cart (session-based)
  resource :cart, only: [:show], controller: 'cart' do
    member do
      post :add
      put :update
      delete :clear
      get :validate
      post :validate
    end
    
    # Remove specific item from cart
    delete :remove, to: 'cart#remove'
  end
  
  # Orders and checkout
  resources :orders, only: [:index, :show, :create, :update] do
    member do
      delete :cancel
      get :status
    end
    
    # Payments for orders
    resources :payments, only: [:index, :create, :show] do
      member do
        post :confirm
        post :refund
      end
    end
  end
  
  # Direct payment access
  resources :payments, only: [:show] do
    member do
      post :refund
    end
  end
  
  # Stripe webhooks
  post '/payments/webhook', to: 'payments#webhook'
  
  # API info endpoint
  get '/api/info', to: 'application#api_info'
end
