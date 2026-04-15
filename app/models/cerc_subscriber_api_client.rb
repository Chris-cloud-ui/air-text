class CercSubscriberApiClient
  class << self
    def find_subscriber(email:, phone:)
      query = {
        email: email,
        phone: phone
      }

      request("find-subscriber", :get, query)
    end

    def send_verification_code(medium:, verification_code:, email: nil, phone: nil)
      puts "send_verification_code"
      query = {
        medium: medium,
        verificationCode: verification_code,
        expiryString: "15 minutes",
        email: email,
        phone: phone
      }

      request("send-verification-code", :post, query)
    end

    def get_subscriptions(subscriber_id)
      request("subscriptions/#{subscriber_id}", :get)
    end

    def create_subscription(zone:, medium:, ampm:, subscriber_id: nil, phone: nil, email: nil, subscriber_details: nil)
      query = {
        subscriberId: subscriber_id,
        zone: zone,
        mode: medium,
        phone: phone,
        email: email,
        time: ampm,
        subscriberDetails: subscriber_details
      }

      request("subscriptions", :post, query)
    end

    def delete_subscription(subscriber_id, subscription_id)
      query = {
        subscriberId: subscriber_id,
        subscriptionId: subscription_id
      }

      request("subscriptions", :delete, query)
    end

    private

    def request(endpoint, method, query = {}, body = nil)
      puts "request"
      base_url = ENV.fetch("CERC_SUBSCRIBER_API_HOST_URL")
      puts base_url
      headers = {"x-api-key" => ENV.fetch("CERC_SUBSCRIBER_API_KEY")}
      
      if method == :post
        puts "post"
        HTTParty.post("#{base_url}/#{endpoint}", headers: headers, query: query.compact, body: body)
        puts "post end"
      else
        puts "get"
        HTTParty.get("#{base_url}/#{endpoint}", headers: headers, query: query.compact)
      end
    end
  end
end
