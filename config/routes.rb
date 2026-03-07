Rails.application.routes.draw do
  devise_for :users

  # Authenticated routes
  authenticate :user do
    root "dashboard#index", as: :authenticated_root

    get "dashboard", to: "dashboard#index"

    resources :books do
      member do
        post :start_reading
        post :mark_completed
        post :update_progress
      end
      resources :reading_sessions, only: [:new, :create], shallow: true do
        collection do
          post :start
        end
      end
    end

    resources :reading_sessions, only: [:index, :show, :edit, :update, :destroy] do
      member do
        post :complete
      end
    end

    resources :reading_goals, except: [:index] do
      member do
        post :mark_completed
        post :mark_abandoned
        get :redistribute
        post :redistribute
        post :catch_up
        post :resolve_discrepancy
      end
      resources :daily_quotas, only: [:update], shallow: true
    end

    resource :pipeline, only: [:show], controller: "pipeline"
    resource :profile, only: [:show, :update]
    resource :reading_list, only: [:show], controller: "reading_list"

    namespace :api do
      namespace :v1 do
        resources :pipeline, only: [:index], controller: "pipeline" do
          member do
            patch :update
          end
        end
        resources :active_books, only: [:index]
        resources :book_search, only: [:index]
        resources :reading_list, only: [:create, :destroy], controller: "reading_list" do
          collection do
            post :reorder
          end
        end
      end
    end
  end

  # Unauthenticated root
  root "home#index"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
