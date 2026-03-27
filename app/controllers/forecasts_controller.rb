class ForecastsController < ApplicationController
  def show
    load_options

    @forecasts = CercForecastService.latest_forecasts(@zone).data
    @day_forecast = forecast_for_day(@day, @forecasts)
    @share_message = @day_forecast.share_message

    @maptiler_api_key = ENV.fetch("MAPTILER_API_KEY")
    @map_lat = params.fetch("lat", nil)
    @map_lon = params.fetch("lon", nil)
    @map_zoom = params.fetch("zoom", nil)

    @hide_alert_banner = true

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("forecast-tabs-frame", partial: "forecasts/forecast_tabs"),
          turbo_stream.replace("alert-guidance-frame", partial: "forecasts/alert_guidance"),
          turbo_stream.replace("predictions-frame", partial: "forecasts/predictions"),
          turbo_stream.replace("sharing-frame", partial: "forecasts/sharing")
        ]
      end
      format.html
    end
  end

  def alerts
    @alerts = {}
    CercForecastService.latest_forecasts.each do |alert|
      zone_group = alert.zone.zone_group.name
      @alerts[zone_group] ||= []
      @alerts[zone_group] << alert if alert.data.map { |f| f.air_quality_alert? }.count(true).positive?
    end

    # Sort the alerts by type
    @alerts.each do |zone_group, alerts|
      alerts.sort_by! { |alert| [-alert.zone.cerc_type, alert.zone.name] }
    end

    @hide_alert_banner = true
  end

  def pollutant_forecasts
    load_options
    latest_forecasts = CercForecastService.latest_forecasts

    pollutant_forecasts = latest_forecasts.each_with_object({}) do |zone_forecasts, hash|
      zone_name = zone_forecasts.data.first.zone[:name]
      hash[zone_name] = forecast_for_day(@day, zone_forecasts.pollutant_forecasts(@pollutant))
    end

    render json: pollutant_forecasts
  end

  def load_options
    @zone = zone
    @date = date
    @day = @date ? day_from_date(@date) : "today"
    @pollutant = pollutant
    @dummy = ENV.fetch("DUMMY_FORECAST", nil)
  end

  private

  def day_from_date(date)
    if date <= Date.today
      "today"
    elsif date == Date.tomorrow
      "tomorrow"
    elsif date >= Date.tomorrow
      "day_after_tomorrow"
    end
  end

  def forecast_for_day(day, forecasts)
    case day
    when "today"
      forecasts.first
    when "tomorrow"
      forecasts.second
    when "day_after_tomorrow"
      forecasts.third
    end
  end

  def zone
    Zone.find_by!(name: params[:zone])
  rescue ActiveRecord::RecordNotFound
    Zone.default
  end

  def date
    return Date.parse(params.fetch("date")) if params[:date].present?

    Date.today
  rescue ArgumentError
    Date.today # default to today
  end

  def pollutant
    return params.fetch("pollutant", "Total") if %w[Total PM10 PM2_5 NO2 O3].include?(params.dig("pollutant"))

    "Total" # default to Total
  end
end
