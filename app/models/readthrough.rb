class Readthrough < ApplicationRecord
  after_initialize :set_default_start_date

  belongs_to :user_book

  private

  def set_default_start_date
    self.start_date ||= Date.today if new_record?
  end
end
