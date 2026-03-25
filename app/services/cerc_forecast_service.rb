class CercForecastService
  class << self
    def latest_forecasts(zone = nil)
      refresh_cache if CachedForecast.stale?

      if zone.nil?
        return dummy_forecasts if dummy_forecast?
        CachedForecast.latest_for_all_zones
      else
        return dummy_forecasts.first if dummy_forecast?
        CachedForecast.latest_for(zone)
      end
    end

    def latest_forecast_date(zone = nil)
      latest_forecasts(zone).first&.obtained_at
    end

    private

    def refresh_cache
      cerc_forecasts = CercForecastApiClient.latest_forecasts
      obtained_at = Time.zone.parse(cerc_forecasts.fetch("forecastdate"))

      cerc_forecasts.fetch("zones").each do |zone|
        CachedForecast.store(
          zone_forecasts(zone, obtained_at: obtained_at)
        )
      end
    end

    def dummy_forecast?
      ENV.fetch("DUMMY_FORECAST", nil).present?
    end

    def dummy_forecasts
      central_london = Zone.find_by(name: "Central London")
      forecast_sets = {
        1 => [ # A high, moderate, and low air pollution forecast
          FactoryBot.build(:forecast, zone: central_london, air_pollution: FactoryBot.build(:air_pollution_prediction, :high), date: Date.today),
          FactoryBot.build(:forecast, zone: central_london, air_pollution: FactoryBot.build(:air_pollution_prediction, :moderate), date: Date.tomorrow),
          FactoryBot.build(:forecast, zone: central_london, air_pollution: FactoryBot.build(:air_pollution_prediction, :low), date: Date.tomorrow + 1.day)
        ],
        2 => [ # High UV, moderate pollen, and extreme temperature forecast
          FactoryBot.build(:forecast, zone: central_london, uv: 6, date: Date.today),
          FactoryBot.build(:forecast, zone: central_london, pollen: 8, date: Date.tomorrow),
          FactoryBot.build(:forecast, zone: central_london, temperature: {min: -10, max: 40}, date: Date.tomorrow + 1.day)
        ]
      }

      set_number = (ENV.fetch("DUMMY_FORECAST").presence || 1).to_i
      [FactoryBot.build(:cached_forecast, data: forecast_sets[set_number], zone: central_london)]
    end

    def zone_forecasts(zone, obtained_at: Time.current)
      zone["forecasts"].map do |forecast|
        f = Forecast.new({
          obtained_at: obtained_at,
          date: Date.parse(forecast.fetch("forecast_date")),
          zone: {
            id: zone.fetch("zone_id"),
            name: zone.fetch("zone_name"),
            type: zone.fetch("zone_type")
          },

          air_pollution: {
            forecasted_at: Time.zone.parse(forecast.fetch("pollution_version").to_s),
            no2: forecast.fetch("NO2"),
            pm10: forecast.fetch("PM10"),
            pm2_5: forecast.fetch("PM2.5"),
            o3: forecast.fetch("O3"),
            total: forecast.fetch("total"),
            label: forecast.fetch("total_status")
          },

          uv: forecast.fetch("uv"),
          pollen: forecast.fetch("pollen"),
          temperature: {
            min: forecast.fetch("temp_min"),
            max: forecast.fetch("temp_max")
          }
        })
        Rails.logger.info("Forecast object: #{f.inspect}") # logs the whole Forecast object
        f
      end
    end
  end
end
