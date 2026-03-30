import { Controller } from "@hotwired/stimulus";
import { MaptilerLayer } from "@maptiler/leaflet-maptilersdk";
import "@maptiler/geocoding-control/leaflet"; // Geocoding (search) control
import { LocateControl } from "leaflet.locatecontrol"; // Geolocation control
import "leaflet.fullscreen"; // Fullscreen control
import * as zones from "../zone_boundaries/zone-boundaries";
import booleanPointInPolygon from "@turf/boolean-point-in-polygon";

export default class MapController extends Controller {
  static targets = [
    "map",
    "pollutantSelector",
    "zoneSelector",
    "dateSelector",
    "latField",
    "lngField",
    "zoomField",
  ];

  layers = {};
  defaultMapSettings = {
    pollutant: "Total",
    date: new Date().toJSON().slice(0, 10),
    center: [51.510357, -0.116773], // Big Ben, lat lng
    zoom: 8,
    maptilerApiKey: document
      .getElementById("map")
      .getAttribute("data-maptiler-api-key"),
  };

  mapTargetConnected() {
    this.updateSettings();
    this.createMap();
    this.updateForecastZone(this.settings.center);
  }

  updateSettings() {
    const pollutant = this.pollutantSelectorTarget.querySelector(
      "input[name=pollutant]:checked"
    ).value;
    const date = this.dateSelectorTarget.value;
    const url = new URL(window.location.href);

    const zone = url.searchParams.get("zone");
    const lat =
      parseFloat(url.searchParams.get("lat")) ||
      this.getZoneCoordinates(zone)?.[1];
    const lng =
      parseFloat(url.searchParams.get("lng")) ||
      this.getZoneCoordinates(zone)?.[0];
    const center = lat && lng ? [lat, lng] : null;
    const zoom = parseInt(url.searchParams.get("zoom")) || (zone ? 13 : null);

    const newSettings = {
      pollutant: pollutant,
      date: date,
      center: center || this.defaultMapSettings.center,
      zoom: zoom || this.defaultMapSettings.zoom,
    };
    this.settings = Object.assign({}, this.defaultMapSettings, newSettings);
  }

  getZoneCoordinates(searchedZone) {
    for (const [, zone] of Object.entries(zones)) {
      if (zone.properties.name === searchedZone) {
        return zone.properties.center;
      }
    }
  }

  createMap() {
    this.map = L.map("map", {
      center: this.settings.center,
      zoom: this.settings.zoom,
      zoomControl: false,
      fullscreenControl: true,
      fullscreenControlOptions: {
        position: "bottomleft",
      },
    });

    this.addSearchControl();
    this.addGeolocationControl();
    this.addZoomControl();

    // Ordered from bottom to top
    this.map.createPane("street-map");
    this.map.getPane("street-map").style.opacity = 1;
    this.map.getPane("street-map").style.zIndex = 420;
    this.addStreetMapLayer();

    this.map.createPane("pollution");
    this.map.getPane("pollution").style.opacity = 0.6;
    this.map.getPane("pollution").style.zIndex = 450;
    this.addPollutionLayer();

    this.map.createPane("place-names");
    this.map.getPane("place-names").style.zIndex = 451;
    this.addPlaceNamesLayer();

    this.map.createPane("zones");
    this.map.getPane("zones").style.zIndex = 452;
    this.addZonesLayer();

    this.map.on("zoomend moveend", () => {
      this.updateUrl();
      this.updateForecastZone([
        this.map.getCenter().lat,
        this.map.getCenter().lng,
      ]);
    });
  }

  updateForecastZone(coordinatesLatLng) {
    if (!coordinatesLatLng) {
      return;
    }

    const coordinatesLngLat = [coordinatesLatLng[1], coordinatesLatLng[0]];
    const zones = this.findZones(coordinatesLngLat);
    let zone;
    if (!zones || zones.length === 0) {
      return;
    } else if (zones.length > 1) {
      zone = zones[this.map.getZoom() <= 12 ? 1 : 0]; // Show more specific zone at higher zoom
    } else {
      zone = zones[0];
    }

    this.zoneSelectorTarget.value = zone.properties.name;
    this.zoneSelectorTarget.form.requestSubmit();
  }

  updateUrl() {
    const url = new URL(window.location.href);

    const lat = this.map.getCenter().lat.toFixed(6);
    url.searchParams.set("lat", lat);
    this.latFieldTarget.value = lat;

    const lng = this.map.getCenter().lng.toFixed(6);
    url.searchParams.set("lng", lng);
    this.lngFieldTarget.value = lng;

    const zoom = this.map.getZoom();
    url.searchParams.set("zoom", zoom);
    this.zoomFieldTarget.value = zoom;

    window.history.replaceState({}, "", url);
  }

  addZoomControl() {
    L.control
      .zoom({
        position: "bottomleft",
      })
      .addTo(this.map);
  }

  addSearchControl() {
    L.control
      .maptilerGeocoding({
        apiKey: this.settings.maptilerApiKey,
        position: "topleft",
        country: ["GB"],
        placeholder: "Enter a place, address, or postcode",
        proximity: [-0.116773, 51.510357], // Big Ben, lng lat
        types: [
          "region",
          "subregion",
          "county",
          "joint_municipality",
          "joint_submunicipality",
          "municipality",
          "municipal_district",
          "locality",
          "neighbourhood",
          "place",
          "postal_code",
          "address",
          "road",
          "poi",
        ],
      })
      .on("pick", (e) => {
        this.updateForecastZone(e.feature?.geometry?.coordinates);
      })
      .addTo(this.map);

    const searchButton = document.getElementsByClassName("search-button")[0];
    searchButton.setAttribute("aria-label", "Search for a location");
  }

  addGeolocationControl() {
    new LocateControl({
      position: "topleft",
    }).addTo(this.map);
  }

  addStreetMapLayer() {
    const streetMap = new MaptilerLayer({
      apiKey: this.settings.maptilerApiKey,
      style: "019c0507-d879-7c46-8d06-83ae78c649ea",  
      pane: "street-map",
      maxZoom: 20,        
      maxNativeZoom: 20   
    });
    this.map.addLayer(streetMap);
    streetMap.getCanvas().removeAttribute("tabindex");
    streetMap.getCanvas().setAttribute("aria-label", "Street map layer");
  }

  addPlaceNamesLayer() {
    const placeNames = new MaptilerLayer({
      apiKey: this.settings.maptilerApiKey,
      style: "019d3e7f-6a90-7b8a-af98-1cb2753c5d79",
      pane: "place-names",
    });
    this.map.addLayer(placeNames);
    placeNames.getCanvas().removeAttribute("tabindex");
    placeNames.getCanvas().setAttribute("aria-label", "Place names map layer");
  }

  addPollutionLayer() {
    this.layers.pollution = this.pollutionLayer(
      this.settings.pollutant,
      this.settings.date
    );
    this.map.addLayer(this.layers.pollution);
  }

  pollutionLayer(pollutant, date) {
    var pollcj;
    if (pollutant=="PM2_5") {
      pollcj = "PM25";
    } else {
      pollcj = pollutant;
    }
    return L.tileLayer.wms("https://airtext.info/geoserver/wms?", {
      layers: `london:${pollcj}`,
      time: date,
      transparent: true,
      format: "image/png",
      opacity: 1,
      pane: "pollution",
      styles: `daqi${pollcj}`,
    });
  }

  addZonesLayer() {
    const zoneBoundaryLayers = this.zoneBoundariesLayers();
    zoneBoundaryLayers.forEach((layer) => layer.addTo(this.map));
    this.updateZoneBoundaryLayerStyles(zoneBoundaryLayers);

    this.map.on("zoomend", () => {
      this.updateZoneBoundaryLayerStyles(zoneBoundaryLayers);
    });
  }

  zoneBoundariesLayers() {
    const zoneBoundaryLayers = [];

    for (const [, zone] of Object.entries(zones)) {
      const layer = L.geoJSON(zone, { pane: "zones" });
      zoneBoundaryLayers.push(layer);
    }

    return zoneBoundaryLayers;
  }

  updateZoneBoundaryLayerStyles(zoneBoundaryLayers) {
    const zoom = this.map.getZoom();

    zoneBoundaryLayers.forEach((layer) => {
      layer.setStyle({
        weight: 0.1 * 20 ** (zoom / 14), // Scale the stroke width with zoom
        color: "black", // stroke color
        fill: false,
      });
    });
  }

  async updateZoneLabels() {
    const pollutantForecasts = await this.getForecastData();

    // Remove existing zone labels
    this.layers.zoneLabels?.forEach((marker) => this.map.removeLayer(marker));
    this.layers.zoneLabels = [];

    // Only show the zone labels when the map is zoomed in enough
    for (const [, zone] of Object.entries(zones)) {
      const startZoom = 9 + (zone.properties.londonBorough ? 2 : 0); // Only show London borough labels at higher zoom
      const endZoom = 20;

      // Add the marker to the map if within the zoom range
      if (this.map.getZoom() >= startZoom && this.map.getZoom() <= endZoom) {
        const center = {
          lat: zone.properties.center[1],
          lng: zone.properties.center[0],
        };
        const pollutantValue = pollutantForecasts[zone.properties.name];

        const html =
          `<div class="wrapper">` +
          (pollutantValue
            ? `<span class="daqi-indicator daqi-level-${pollutantValue}">${pollutantValue}</span>`
            : "") +
          `<span class="zone-name">${zone.properties.name}</span>` +
          `</div>`;

        const marker = L.marker(center, {
          icon: L.divIcon({
            className:
              "zone-label " + `zone-label-level-${zone.properties.level}`,
            html: html,
          }),
          keyboard: false,
        });
        marker.addTo(this.map);
        this.layers.zoneLabels.push(marker);
      }
    }
  }

  findZones(coordinatesLngLat) {
    if (!coordinatesLngLat) {
      return;
    }

    const matches = [];
    for (const [, zone] of Object.entries(zones)) {
      // Coordinated have to be in the format [longitude, latitude]
      if (booleanPointInPolygon(coordinatesLngLat, zone)) {
        matches.push(zone);
      }
    }

    // Sort by zone level so more specific zones are returned first
    matches.sort((a, b) => b.properties.level - a.properties.level);

    return matches;
  }

  updateMap() {
    this.updateSettings();
    this.updatePollutionLayer();
    this.updateZoneLabels();
  }

  updatePollutionLayer() {
    this.map.removeLayer(this.layers.pollution);
    this.addPollutionLayer();
  }

  async getForecastData() {
    const pollutant = this.settings.pollutant;
    const date = this.settings.date;

    const response = await fetch(
      `/pollutant_forecasts?pollutant=${pollutant}&date=${date}`
    );
    return response.json();
  }

  openDaqiScaleFlyout(e) {
    e.preventDefault();
    document.querySelector(".mobile-flyout").classList.add("open");
    document.querySelector(".mobile-flyout .close").focus();
  }

  closeDaqiScaleFlyout(e) {
    e.preventDefault();
    document.querySelector(".mobile-flyout").classList.remove("open");
    document.querySelector(".colour-scale-link button").focus();
  }
}
