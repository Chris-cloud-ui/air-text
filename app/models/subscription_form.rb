class SubscriptionForm
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveRecord::Callbacks

  attribute :current_step

  # contact_details
  attribute :receive_email
  attribute :receive_sms
  attribute :receive_voice
  attribute :email
  attribute :sms_number
  attribute :voice_number

  validate :one_contact_method_present?, if: -> { after_step?("contact_details") }
  validates :email, presence: {message: "You must provide an email address"}, if: -> { receiving?(:email) && after_step?("contact_details") }
  validates :sms_number, presence: {message: "You must provide a mobile number to receive texts"}, if: -> { receiving?(:sms) && after_step?("contact_details") }
  validates :voice_number, presence: {message: "You must provide a phone number to receive voicemail"}, if: -> { receiving?(:voice) && after_step?("contact_details") }

  # contact_verification
  attribute :verification_code_email
  attribute :verification_code_sms_number
  attribute :verification_code_voice_number

  before_validation do
    self.verification_code_email = verification_code_email&.join if verification_code_email.is_a?(Array)
    self.verification_code_sms_number = verification_code_sms_number&.join if verification_code_sms_number.is_a?(Array)
    self.verification_code_voice_number = verification_code_voice_number&.join if verification_code_voice_number.is_a?(Array)
  end

  validates :verification_code_email, presence: {message: "You must enter the verification code"}, if: -> { on_step?("email_verification") && verification_enabled? }
  validate :verification_code_email_correct?, if: -> { on_step?("email_verification") && verification_enabled? }
  validates :verification_code_sms_number, presence: {message: "You must enter the verification code"}, if: -> { on_step?("sms_number_verification") && verification_enabled? }
  validate :verification_code_sms_correct?, if: -> { on_step?("sms_number_verification") && verification_enabled? }
  validates :verification_code_voice_number, presence: {message: "You must enter the verification code"}, if: -> { on_step?("voice_number_verification") && verification_enabled? }
  validate :verification_code_voice_correct?, if: -> { on_step?("voice_number_verification") && verification_enabled? }

  # zone_selection
  attribute :zone_search
  attribute :zones

  validate :at_least_one_zone_selected?, if: -> { after_step?("zone_selection") }
  validate :no_more_than_5_zones?, if: -> { after_step?("zone_selection") }

  # time_selection
  attribute :time

  validates :time, presence: {message: "You must select a time to receive alerts"}, if: -> { after_step?("time_selection") }

  # wrap_up
  attribute :reason
  attribute :source
  attribute :research
  attribute :terms
  attribute :privacy

  validates :terms, acceptance: {message: "You must agree to the terms and conditions"}, if: -> { after_step?("wrap_up") }
  validates :privacy, acceptance: {message: "You must agree to the privacy policy"}, if: -> { after_step?("wrap_up") }

  TIMES = {
    "AM" => {label: "Morning: 7am", hint: "Alert for the current day (email, text and voicemail)"},
    "PM" => {label: "Evening: 7pm", hint: "Alert for the next day (text and voicemail)"}
  }

  REASONS = {
    health_condition: "I have a health condition that is made worse by air pollution",
    care_for_someone: "Someone I care for has a health condition that is made worse by air pollution",
    concerned: "I am concerned about air pollution generally",
    prefer_not_to_say: "I prefer not to say",
    other: "Other"
  }

  SOURCES = {
    airtext_application_form: "airTEXT application form",
    poster_on_bus: "Poster on bus",
    poster_on_tube: "Poster on tube",
    mayor_of_london: "Mayor of London",
    tfl_air_quality_alerts: "TfL air quality alerts",
    council_website: "Council website",
    council_magazine: "Council magazine",
    breathe_easy_group: "Breathe Easy group",
    barts_health_nhs_trust: "Barts Health NHS trust",
    islington_primary_schools: "Islington primary schools",
    shine: "SHINE (Seasonal Health Interventions Network)",
    merton_cac: "Merton's Clean Air Campaign",
    be_air_aware_campaign: "Be Air Aware Campaign",
    my_doctor: "My doctor",
    local_pharmacist: "Local pharmacist",
    local_council_employee: "Local council employee",
    national_newspaper: "National newspaper",
    local_newspaper: "Local newspaper",
    air_quality_workshop: "Air Quality Workshop",
    a_friend: "A friend",
    tv_radio: "TV/radio",
    web_or_search_engine: "Web or Search Engine",
    twitter: "Twitter",
    facebook: "Facebook",
    other: "Other"
  }

  # Normalization methods

  def assign_attributes(attributes)
    super(normalized_attributes(attributes))
  end

  def normalized_attributes(attributes)
    attributes["zones"] = normalized_zones(attributes["zones"]) if attributes["zones"]
    attributes
  end

  def normalized_zones(zones)
    zones.reject(&:empty?)
  end

  # Validation methods

  def on_step?(step_name)
    current_step == step_name
  end

  def after_step?(step_name)
    current_step_index = current_step.present? ? SubscriptionsController::ALL_STEPS.flatten.index(current_step.to_sym) : 0
    this_step_index = SubscriptionsController::ALL_STEPS.flatten.index(step_name.to_sym) || 0

    current_step_index >= this_step_index
  end

  def one_contact_method_present?
    errors.add(:base, "You must select at least one contact method") unless receiving?(:email) || receiving?(:sms) || receiving?(:voice)
  end

  def verification_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("VERIFICATION_ENABLED", true))
  end

  def verification_code_email_correct?
    errors.add(:verification_code_email, "The verification code you entered is incorrect") unless VerificationCode.verify(verification_code_email, email)
  end

  def verification_code_sms_correct?
    errors.add(:verification_code_sms, "The verification code you entered is incorrect") unless VerificationCode.verify(verification_code_sms_number, sms_number)
  end

  def verification_code_voice_correct?
    errors.add(:verification_code_voice, "The verification code you entered is incorrect") unless VerificationCode.verify(verification_code_voice_number, voice_number)
  end

  def at_least_one_zone_selected?
    errors.add(:zones, "You must select at least one zone to receive alerts for") unless zones&.count&.positive?
  end

  def no_more_than_5_zones?
    errors.add(:zones, "You can select a maximum of 5 zones") if zones&.count&.> 5
  end

  def receiving?(method)
    send(:"receive_#{method}").to_i.positive?
  end

  # Creation methods

  def save
    if current_step == "confirmation" && valid?
      create_subscriptions
      true
    else
      valid?
    end
  end

  def mediums
    [
      ("email" if receive_email),
      ("sms" if receive_sms),
      ("voicemail" if receive_voice)
    ].compact
  end

  
  def create_subscriptions

    subscriberid = nil
    
    zones.compact.each do |zone|
      mediums.each do |medium|
        if subscriberid.nil?
          puts "find_subscriber"
          puts email
          puts sms_number
          puts voice_number
          response = CercSubscriberApiClient.find_subscriber(
            email: email,
            phone: sms_number || voice_number
          )

          parsed = response.parsed_response
          puts "response"
          puts parsed
          if parsed.nil? || parsed.empty?
            puts "empty"
            create_subscription(zone, medium, nil)
          else
            puts "found"
            puts parsed["subscriberId"]
            subscriberid=parsed["subscriberId"]
            create_subscription(zone, medium, subscriberid)
          end
        else
          puts "continue"
          create_subscription(zone, medium, subscriberid)
        end
        
        
          
      end
    end
  end

  def create_subscription(zone, medium, subscriber_id)
  args = {
    zone: zone,
    medium: medium,
    ampm: time,
    phone: (sms_number if medium == "sms") || (voice_number if medium == "voice"),
    email: (email if medium == "email")
  }

  if subscriber_id.nil?
    args[:subscriber_details] = {
      "whySignup" => reason,
      "howHeard" => source,
      "allowContact" => research
    }
  else
    args[:subscriber_details] => subscriber_id,
  end

  CercSubscriberApiClient.create_subscription(**args)
end


end
