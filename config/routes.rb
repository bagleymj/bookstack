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
      resources :reading_sessions, only: [:new, :create], shallow: true
    end

    resources :reading_sessions, only: [:index, :show, :edit, :update, :destroy] do
      member do
        post :complete
      end
    end

    resources :reading_goals do
      member do
        post :mark_completed
        post :mark_abandoned
        post :redistribute
      end
      resources :daily_quotas, only: [:update], shallow: true
    end

    resources :pipelines do
      member do
        post :auto_schedule
      end
      resources :pipeline_books, only: [:create, :update, :destroy], shallow: true do
        collection do
          post :reorder
        end
      end
    end

    # API endpoints for the pipeline chart
    namespace :api do
      namespace :v1 do
        resources :pipelines, only: [] do
          member do
            get :timeline_data
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
