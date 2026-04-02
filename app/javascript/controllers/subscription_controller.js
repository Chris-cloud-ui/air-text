import { Controller } from "@hotwired/stimulus";
import { useDebounce } from "stimulus-use";
import { geocoding } from "@maptiler/client";
import * as zones from "../zone_boundaries/zone-boundaries";
import booleanPointInPolygon from "@turf/boolean-point-in-polygon";

export default class SubscriptionController extends Controller {
  static targets = [
    "email",
    "sms",
    "voice",
    "searchField",
    "searchResults",
    "selectedZones",
    "resendVerificationButton",
  ];
  static debounces = ["search"];

  connect() {
    useDebounce(this);
  }

  // Contact details
  toggleEmail() {
    this.emailTarget.classList.toggle("hidden");
  }

  toggleSms() {
    this.smsTarget.classList.toggle("hidden");
  }

  toggleVoice() {
    this.voiceTarget.classList.toggle("hidden");
  }

  resendVerification() {
    const mode = this.resendVerificationButtonTarget.dataset.medium;
    this.resendVerificationButtonTarget.textContent =
      "resend the code – sending...";
    fetch(`/resend_verification_code?medium=${mode}`).then((response) => {
      if (response.ok) {
        this.resendVerificationButtonTarget.textContent =
          "resend the code – sent successfully";
      } else {
        this.resendVerificationButtonTarget.textContent =
          "resend the code – an error occurred";
      }
    });
  }

  // Zone selection
  searchFieldTargetConnected() {
    this.maptilerApiKey = this.searchFieldTarget.dataset.maptilerApiKey;
  }

  async search() {
    const userInput = this.searchFieldTarget.value;
    const coordinates = await this.geoCode(userInput);
    const zones = this.findZones(coordinates);
    this.displaySearchResults(zones);
  }

  async geoCode(location) {
    if (!location) {
      return;
    }

    const result = await geocoding.forward(location, {
      apiKey: this.maptilerApiKey,
      country: ["GB"],
      proximity: [-0.116773, 51.510357],
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
    });

    return result?.features[0]?.geometry?.coordinates;
  }

  findZones(point) {
    if (!point) {
      return;
    }

    const matches = [];
    // Point has to be in the format [longitude, latitude]
    for (const [, zone] of Object.entries(zones)) {
      if (booleanPointInPolygon(point, zone)) {
        matches.push(zone);
      }
    }

    // Sort by zone level so more specific zones are returned first
    matches.sort((a, b) => b.properties.level - a.properties.level);

    return matches;
  }

  displaySearchResults(results) {
    this.searchResultsTarget.innerHTML = "";
    this.searchResultsTarget.classList.remove("hidden");

    if (!results || results.length === 0) {
      this.searchResultsTarget.classList.add("no-results");
      const li = document.createElement("li");
      li.textContent = "No results found within the area covered by airTEXT";
      this.searchResultsTarget.appendChild(li);
      return;
    }

    results.forEach((result) => {
      if (this.tag(result.properties.name)) {
        return;
      }

      this.searchResultsTarget.classList.remove("no-results");
      const li = document.createElement("li");
      li.textContent = result.properties.name;
      li.dataset.action = "click->subscription#selectSearchResult";
      li.classList.add("zone-tag");
      this.searchResultsTarget.appendChild(li);
    });
  }

  selectSearchResult(event) {
    const zoneName = event.target.textContent;
    this.addSelectedZone(zoneName);

    // Remove from search results
    event.target.remove();
  }

  selectedZonesTargetConnected() {
    const checkboxes = document.querySelectorAll(
      "input[name='subscription_form[zones][]']"
    );
    checkboxes.forEach((checkbox) => {
      checkbox.addEventListener("change", (event) =>
        this.checkboxChanged(event)
      );

      if (checkbox.checked) {
        this.addSelectedZone(checkbox.value);
      }
    });
  }

  checkboxChanged(event) {
    const zoneName = event.target.value;
    if (event.target.checked) {
      this.addSelectedZone(zoneName);
    } else {
      this.removeSelectedZone(zoneName);
    }
  }

  setCheckboxState(zone_name, state) {
    const checkbox = document.querySelector(`input[value="${zone_name}"]`);
    //if (checkbox.checked !== state) {
    checkbox.checked = state;
    checkbox.dispatchEvent(new Event("change"));
    //}
  }

  tag(zoneName) {
    return this.selectedZonesTarget.querySelector(
      `li[data-zone-name="${zoneName}"]`
    );
  }

  tagClicked(event) {
    const zoneName = event.target.dataset.zoneName;
    this.setCheckboxState(zoneName, false);
  }

  addSelectedZone(zoneName) {
    if (this.tag(zoneName)) {
      return;
    }

    const tag = document.createElement("li");
    tag.textContent = zoneName;
    tag.classList.add("zone-tag", "selected");
    tag.dataset.zoneName = zoneName;
    tag.dataset.action = "click->subscription#tagClicked";
    this.selectedZonesTarget.appendChild(tag);

    this.setCheckboxState(zoneName, true);
  }

  removeSelectedZone(zoneName) {
    this.tag(zoneName).remove();
  }

  processVerificationCodeInput(event) {
    const input = event.target;
    const value = input.value;

    // When a verification code input is filled, focus the next input
    // When an input is emptied, focus the previous input

    if (value.length === 1) {
      input.nextElementSibling?.focus();
    } else if (value.length === 0) {
      input.previousElementSibling?.focus();
    }
  }

  processVerificationCodePaste(event) {
    const input = event.target;
    const value = event.clipboardData.getData("text");

    // When a code is pasted, fill the inputs in order

    if (value.length === 6) {
      input.parentElement.querySelectorAll("input").forEach((input, index) => {
        input.value = value[index];
        input.focus();
      });
    }
  }

  processVerificationCodeMove(event) {
    const input = event.target;

    // If right arrow key is pressed, focus next input
    if (event.keyCode === 39) {
      input.nextElementSibling.focus();
    }

    // If left arrow key is pressed, focus previous input
    if (event.keyCode === 37) {
      input.previousElementSibling.focus();
    }
  }
}
