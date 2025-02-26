# config/routes.rb

Rails.application.routes.draw do
  # Authentication
  post '/signup', to: 'users#create'
  post '/login',  to: 'sessions#create'

  # Phone verification
  post '/verify_phone', to: 'users#verify_phone'
  post '/resend_code',  to: 'users#resend_code'

  # Password resets
  post  '/password/forgot', to: 'passwords#forgot'
  patch '/password/reset',  to: 'passwords#reset'

  # Standard REST resources
  resources :restaurants, only: [:index, :show, :create, :update, :destroy]
  resources :seat_sections, only: [:index, :show, :create, :update, :destroy]

  resources :seats, only: [:index, :show, :create, :update, :destroy] do
    collection do
      post :bulk_update
    end
  end

  resources :reservations, only: [:index, :show, :create, :update, :destroy]
  resources :waitlist_entries, only: [:index, :show, :create, :update, :destroy]

  resources :seat_allocations, only: [:index, :create, :update, :destroy] do
    collection do
      post :multi_create
      post :reserve
      post :arrive
      post :no_show
      post :cancel
      post :finish
    end
  end

  resources :menus, only: [:index, :show, :create, :update, :destroy]
  resources :menu_items, only: [:index, :show, :create, :update, :destroy]
  resources :notifications, only: [:index, :show, :create, :update, :destroy]

  # Layouts
  resources :layouts, only: [:index, :show, :create, :update, :destroy] do
    member do
      post :activate
    end
  end

  # Availability
  get '/availability', to: 'availability#index'

  # -------------------------
  # PUBLIC categories endpoint
  # -------------------------
  resources :categories, only: [:index]

  # -------------------------
  # Admin namespace
  # -------------------------
  namespace :admin do
    # Restaurant settings
    resource :settings, only: [:show, :update]

    # Site settings (hero/spinner)
    resource :site_settings, only: [:show, :update]

    # Operating Hours
    resources :operating_hours, only: [:index, :update]

    # Special Events
    resources :special_events, only: [:index, :show, :create, :update, :destroy]

    # Admin categories => for create/update/delete
    resources :categories, only: [:index, :create, :update, :destroy]

    # Admin analytics
    get 'analytics/customer_orders',    to: 'analytics#customer_orders'
    get 'analytics/revenue_trend',     to: 'analytics#revenue_trend'
    get 'analytics/top_items',         to: 'analytics#top_items'
    get 'analytics/income_statement',  to: 'analytics#income_statement'
    
    # Restaurant settings
    get 'restaurant/allowed_origins',  to: 'restaurant#allowed_origins'
    post 'restaurant/allowed_origins', to: 'restaurant#update_allowed_origins'

    # Admin users => create/edit/delete + resend_invite
    resources :users, only: [:index, :create, :update, :destroy] do
      member do
        post :resend_invite
      end
    end
  end

  # For ordering
  resources :orders, only: [:index, :show, :create, :update, :destroy]
  resources :promo_codes, only: [:index, :show, :create, :update, :destroy]
  resources :menus, only: [:index, :show, :create, :update, :destroy]

  # Enhanced menu_items with image uploading & option groups
  resources :menu_items do
    member do
      post :upload_image
    end

    # For listing or creating option groups under a given menu item:
    resources :option_groups, only: [:index, :create]
  end

  # For updating or deleting an option group (requires just the group ID):
  resources :option_groups, only: [:update, :destroy] do
    # For creating options under a specific option group:
    resources :options, only: [:create]
  end

  # For updating or deleting a specific option (requires just the option ID)
  resources :options, only: [:update, :destroy]

  # Polling route for orders
  get '/orders/new_since/:id', to: 'orders#new_since'

  resources :inventory_statuses, only: [:index, :show, :update]

  # Profile
  get   '/profile', to: 'users#show_profile'
  patch '/profile', to: 'users#update_profile'
end
