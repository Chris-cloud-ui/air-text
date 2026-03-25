# frozen_string_literal: true

class UvPredictionComponent < PredictionComponent
  def name
    "Ultraviolet (UV) rays"
  end

  def sentence_name
    "UV"
  end

  def css_name
    "uv"
  end

  def level_label
    case @value
    when 1..2
      "Low"
    when 3..5
      "Moderate"
    when 6..7
      "High"
    when 8..10
      "Very high"
    else
      "Low"
    end
  end
end
