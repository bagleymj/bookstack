class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Associations
  has_many :books, dependent: :destroy
  has_many :reading_sessions, dependent: :destroy
  has_many :reading_goals, dependent: :destroy
  has_one :user_reading_stats, dependent: :destroy

  # Validations
  validates :default_words_per_page, numericality: { greater_than: 0 }
  validates :default_reading_speed_wpm, numericality: { greater_than: 0 }

  # Callbacks
  after_create :create_reading_stats

  def effective_reading_speed
    user_reading_stats&.average_wpm || default_reading_speed_wpm
  end

  private

  def create_reading_stats
    build_user_reading_stats.save
  end
end
