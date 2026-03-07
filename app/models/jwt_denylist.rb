class JwtDenylist < ApplicationRecord
  self.table_name = "jwt_denylist"

  def self.revoked?(jti)
    exists?(jti: jti)
  end
end
