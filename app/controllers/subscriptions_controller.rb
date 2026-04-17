# frozen_string_literal: true

class SubscriptionsController < ApplicationController
  include Wicked::Wizard

  before_action :set_steps
  before_action :setup_wizard

  ALL_STEPS = [
    %i[
      contact_details
      email_verification
      email_verification_success
      sms_number_verification
      sms_number_verification_success
      voice_number_verification
      voice_number_verification_success
    ],
    %i[
      zone_selection
    ],
    %i[
      time_selection
    ],
    %i[
      wrap_up
      confirmation
    ]
  ]

  def set_steps
    load_form
    form_steps = ALL_STEPS.flatten.dup
    form_steps.reject! { |step| step == :email_verification } unless @form.receiving?(:email)
    form_steps.reject! { |step| step == :email_verification_success } unless @form.receiving?(:email)
    form_steps.reject! { |step| step == :sms_number_verification } unless @form.receiving?(:sms)
    form_steps.reject! { |step| step == :sms_number_verification_success } unless @form.receiving?(:sms)
    form_steps.reject! { |step| step == :voice_number_verification } unless @form.receiving?(:voice)
    form_steps.reject! { |step| step == :voice_number_verification_success } unless @form.receiving?(:voice)

    self.steps = form_steps
  end

  def show
    session[:subscription_form] = nil if params[:reset]
    load_step

    # Validate against the previous step
    @form.current_step = previous_step
    jump_to(previous_step) if @step_number != 1 && (@form.nil? || @form.invalid?)

    # Switch back to the current step
    @form.current_step = step
    case step
    when :email_verification
      send_verification_code("email")
    when :sms_number_verification
      send_verification_code("sms")
    when :voice_number_verification
      send_verification_code("voicemail")
    end

    render_wizard
  end

  def update
    load_step
    session[:subscription_form] = @form.attributes

    if step == :wrap_up && @form.valid?
      @form.create_subscriptions unless session[:subscription_created]
      session[:subscription_created] = true
    end
    render_wizard @form
  end

  def resend_verification_code
    mode = params[:mode]
    send_verification_code(mode)

    render json: {status: "success"}
  end

  private
  
  def send_verification_code(mode)
    case mode
    when "email"
      target = @form.email
    when "sms"
      target = @form.sms_number
    when "voice"
      target = @form.voice_number
    else
      raise "Invalid mode"
    end

    code = VerificationCode.generate(target).code
    # Send a verification code to the user
    CercSubscriberApiClient.send_verification_code(
      verification_code: code,
      medium: mode,
      email: (target if mode == "email"),
      phone: (target if mode != "email")
    )

    # For testing purposes, print the code to the console
    puts "Verification code: #{code}"
  end

  def load_form
    @form ||= SubscriptionForm.new(session[:subscription_form])
    @form.assign_attributes(subscription_params) if params[:subscription_form].present?
  end

  def load_step
    @step_number = steps.index(step).to_i + 1
    @total_steps = steps.count
    @current_step = step
    @first_step = (step == steps.first)
    @final_step = (step == steps.last)
    @step_group = step_group
  end

  def step_group
    ALL_STEPS.each_with_index do |step_group, index|
      return index if step_group.include?(step)
    end
  end

  def subscription_params
    params[:subscription_form].permit(
      :current_step,
      :receive_email,
      :receive_sms,
      :receive_voice,
      :email,
      :sms_number,
      :voice_number,
      :zone_search,
      :time,
      :reason,
      :source,
      :research,
      :terms,
      :privacy,
      zones: [],
      verification_code_email: [],
      verification_code_sms_number: [],
      verification_code_voice_number: []
    )
  end

  def redirect_to_finish_wizard(options = {}, params = {})
    redirect_to forecast_path, notice: "You are now subscribed to receive air pollution alerts."
  end
end
