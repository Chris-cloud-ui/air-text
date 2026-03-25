# frozen_string_literal: true

class TemperaturePredictionComponent < PredictionComponent
  def name
    "Temperature"
  end

  def sentence_name
    "temperature"
  end

  def display_value
    "#{values[:min_c].round}&nbsp;to&nbsp;#{values[:max_c].round}°C / #{values[:min_f].round}&nbsp;to&nbsp;#{values[:max_f].round}°F"
  end

  def values
    {
      min_c: @value[:min],
      max_c: @value[:max],
      min_f: farenheit(@value[:min]),
      max_f: farenheit(@value[:max])
    }
  end

  def farenheit(celsius)
    (celsius * 9 / 5) + 32
  end

  def guidance_visible?
    level_label.present?
  end

  def level_label
    if @value[:min] <= 2
      "Low temp"
    elsif @value[:max] >= 25
      "High temp"
    end
  end
end
