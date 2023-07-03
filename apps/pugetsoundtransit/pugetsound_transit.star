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
DEFAULT_ROUTEID = "40_100240" # 554 Express to Seattle

def main(config):
    # Initialize API token, bus stop, and max predictions number with fallbacks
    api_key = API_KEY

    stop_id = config.get("stop_id")
    if stop_id == None:
        stop_id = DEFAULT_STOPID

    route_id = config.get("route_id")
    if route_id == None:
        route_id = DEFAULT_ROUTEID

    # Call API to get predictions for the given stop
    data = get_times(stop_id, api_key)

    bus_arrivals = []
    for bus in data["data"]["entry"]["arrivalsAndDepartures"]:
        if bus["routeId"] == route_id:
            bus_arrivals.append(
                {
                    "predictedArrivalTime": bus["predictedArrivalTime"],
                    "scheduledArrivalTime": bus["scheduledArrivalTime"],
                }
            )

    if len(bus_arrivals) == 0:
        return render.Root(
            child = render.Text("No buses found"),
        )

    relative_arrivals = []
    now_time = time.now()
    for bus in bus_arrivals:
        # use predicted arrival time if available, otherwise use scheduled arrival time
        if bus["predictedArrivalTime"] > 0:
            nextArrival_unix = int(bus["predictedArrivalTime"] / 1000)

            if bus["predictedArrivalTime"] == bus["scheduledArrivalTime"]:
                # Use green if predicted time is the same as scheduled time.
                prediction_color = "#00ff00"
            elif bus["predictedArrivalTime"] < bus["scheduledArrivalTime"]:
                # Use red if predicted time is earlier than scheduled time.
                prediction_color = "#ff0000"
            else:
                # Use blue if predicted time is later than scheduled time.
                prediction_color = "#0000ff"
        else:
            nextArrival_unix = int(bus["scheduledArrivalTime"] / 1000)
            # Use white if scheduled time is used.
            prediction_color = "#ffffff"
        
        nextArrival_time = time.from_timestamp(nextArrival_unix)
        # Calculate time until next bus
        diff = nextArrival_time - now_time
        diff_minutes = int(diff.minutes)

        relative_arrivals.append(render.Text(content="%s " % diff_minutes, color=prediction_color))

    return render.Root(
        child = render.Column(
            children = [
                render.Row(
                    children = [
                        render.Padding(
                            child = render.Circle(
                                    color="#2B376E",
                                    diameter=14,
                                    child=render.Text(content='554',font='tom-thumb'),
                                ),
                            pad = 1
                        ),
                        render.Column(
                            children = [
                                render.Marquee(
                                    child = render.Text(content="Issaquah Highlands Park & Ride - Bay 4"),
                                    width=48
                                ),
                                render.Marquee(
                                    child = render.Row(
                                        children = relative_arrivals
                                    ),
                                    width=48
                                ),
                            ]
                        )
                    ]
                ),
                render.Row(
                    children = [
                        render.Padding(
                            child = render.Circle(
                                    color="#2B376E",
                                    diameter=14,
                                    child=render.Text(content='554',font='tom-thumb'),
                                ),
                            pad = 1
                        ),
                        render.Column(
                            children = [
                                render.Marquee(
                                    child = render.Text(content="N Mercer Way & 80th Ave SE - Bay 1"),
                                    width=48
                                ),
                                render.Marquee(
                                    child = render.Row(
                                        children = relative_arrivals
                                    ),
                                    width=48
                                ),
                            ]
                        )
                    ]
                ),
            ]
        )
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
            schema.Text(
                id = "route_id",
                name = "Route ID",
                desc = "Bus Route ID",
                icon = "bus",
                default = "40_100240", # 554E
            ),
        ],
    )
