"""
Applet: Puget Sound Transit
Summary: TBD
Description: TBD
Author: tbries
"""

load("cache.star", "cache")
load("encoding/json.star", "json")
load("http.star", "http")
load("math.star", "math")
load("render.star", "render")
load("schema.star", "schema")
load("secret.star", "secret")
load("time.star", "time")

API_BASE = "https://api.pugetsound.onebusaway.org/api"
API_ARRIVALS_AND_DEPARTURES = API_BASE + "/where/arrivals-and-departures-for-stop/%s.json"
API_KEY = ""
DEFAULT_STOPID = "1_64561" # Issaquah Highlands Park & Ride, Bay 4

def main(config):
    # Initialize API token, bus stop, and max predictions number with fallbacks
    api_key = API_KEY

    stop_id = config.get("stop_id")
    if stop_id == None:
        stop_id = DEFAULT_STOPID

    # Call API to get predictions for the given stop
    data = get_times(stop_id, api_key)

    nextArrival_unix = int(data["data"]["entry"]["arrivalsAndDepartures"][0]["predictedArrivalTime"] / 1000)
    nextArrival_time = time.from_timestamp(nextArrival_unix)
    now_time = time.now()

    # Calculate time until next bus
    diff = nextArrival_time - now_time
    diff_minutes = int(diff.minutes)

    return render.Root(
        child = render.Text("data: " + str(diff_minutes)),
    )

def get_times(stop_id, api_key):
    # Call API to get predictions for the given stop
    rep = http.get(
        url = API_ARRIVALS_AND_DEPARTURES % stop_id,
        params = {
            "key": api_key,
            "minutesBefore": "0",
            "minutesAfter": "120",
            "includeReferences": "false",
            "includeSituations": "false",
            "version": "2",
        },
        ttl_seconds = 180,
        )

    if rep.status_code != 200:
        fail("Predictions request failed with status ", rep.status_code)

    return rep.json()

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "stop_id",
                name = "Bus Stop",
                desc = "OBA Bus Stop ID",
                icon = "bus",
                default = "1_64561", # Issaquah Highlands Park & Ride, Bay 4
            ),
        ],
    )
