# frozen_string_literal: true

class PredictionComponent < ViewComponent::Base
  def initialize(value)
    Rails.logger.info(value) 
    @value = value
  end

  def css_name
    name.parameterize
  end

  def display_value
    level_label
  end

  def guidance_visible?
    level_label != "Low"
  end

  def level
    level_label.downcase.tr(" ", "_").to_sym
  end
end
