class UserSubdomain
  def self.matches?(request)
    if ENV['USER_SUBDOMAIN'].present?
      return (request.subdomain.present? &&
              request.subdomain == ENV['USER_SUBDOMAIN'])
    else
      return true
    end
  end
end
