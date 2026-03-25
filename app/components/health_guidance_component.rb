# frozen_string_literal: true

class HealthGuidanceComponent < ViewComponent::Base
  def initialize(type, level, classes: [])
    @type = type&.to_sym
    @level = level&.to_sym
    @classes = classes
    @guidance_blocks = health_guidance[@level] || []
  end

  def health_guidance
    file = File.read("app/assets/guidance/health_guidance.json")
    data_hash = JSON.parse(file, symbolize_names: true)
    data_hash[@type] || {}
  end
end
