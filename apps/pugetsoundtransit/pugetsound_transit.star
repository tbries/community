"""
Applet: Puget Sound Transit
Summary: TBD
Description: TBD
Author: tbries
"""

load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("secret.star", "secret")
load("time.star", "time")

API_KEY = "" # TODO: Encrpt this.
API_BASE = "https://api.pugetsound.onebusaway.org/api"
API_ARRIVALS_AND_DEPARTURES = API_BASE + "/where/arrivals-and-departures-for-stop/%s.json"
API_STOPS = API_BASE + "/where/stop/%s.json"

DEFAULT_STOPID = "1_64561" # Issaquah Highlands Park & Ride, Bay 4
DEFAULT_ROUTEID = "40_100240" # 554 Express to Seattle

def main(config):

    # TODO: Decrypt API key.
    api_key = API_KEY

    scroll_speed_ms = int(config.str("scroll_speed"))
    if scroll_speed_ms <= 0:
        scroll_speed_ms = 100

    stop_id = config.get("stop_id")
    if stop_id == "":
        stop_id = DEFAULT_STOPID

    route_id = config.get("route_id")
    if route_id == "":
        route_id = DEFAULT_ROUTEID

    # Call API to get predictions for the given stop
    bus_arrivals = get_arrival_times(stop_id, route_id, api_key)
    stop_info = get_stop_and_route_info(stop_id, api_key)

    # Get the route info that matches route_id.
    route_info = None
    for route in stop_info["routes"]:
        if route["id"] == route_id:
            route_info = route
            break

    # TODO: Pick a color for the route if one is not provided.
    # TODO: Shorten the 'shortName' if it is too long to fit in the circle.

    return render.Root(
        delay = scroll_speed_ms,
        child = render.Column(
            children = [
                render.Row(
                    children = [
                        render.Padding(
                            child = render.Circle(
                                    color=route_info['color'],
                                    diameter=14,
                                    child=render.Text(content=route_info['shortName'],font='tom-thumb'),
                                ),
                            pad = 1
                        ),
                        render.Column(
                            children = [
                                render.Marquee(
                                    child = render.Text(content=stop_info["name"]),
                                    width=48
                                ),
                                render.Marquee(
                                    child = render.Row(
                                        children = compute_arrival_texts(bus_arrivals)
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


def get_arrival_times(stop_id, route_id, api_key):
    # Call OBA API to get predictions for the given stop.
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

    json_data = rep.json()

    bus_arrivals = []
    for bus in json_data["data"]["entry"]["arrivalsAndDepartures"]:

        # Skip buses with departures disabled, i.e. this will be the bus's last stop.
        if bus["departureEnabled"] == False:
            continue

        if bus["routeId"] == route_id:
            bus_arrivals.append(
                {
                    "predictedArrivalTime": bus["predictedArrivalTime"],
                    "scheduledArrivalTime": bus["scheduledArrivalTime"],
                }
            )

    return bus_arrivals


def get_stop_and_route_info(stop_id, api_key):
    # Call OBA API to get information about the given stop.
    rep = http.get(
        url = API_STOPS % stop_id,
        params = {
            "key": api_key,
            "includeReferences": "true",
            "version": "2",
        },
        ttl_seconds = 3600, # 1 hour cache since this data shouldn't change often.
    )

    if rep.status_code != 200:
        fail("Stop info request failed with status ", rep.status_code)

    json_data = rep.json()

    stop_info = {
        "name": json_data["data"]["entry"]["name"],
        "routes": [],
    }

    # Pull out info for each route that stops at this stop.
    for route in json_data["data"]["references"]["routes"]:
        stop_info["routes"].append(
            {
                "id": route["id"],
                "shortName": route["shortName"],
                "longName": route["longName"],
                "description": route["description"],
                "color": route["color"],
                "agencyId": route["agencyId"],
            }
        )

    return stop_info


def compute_arrival_texts(bus_arrivals):

    if len(bus_arrivals) == 0:
        return [render.Text(content="NONE")]
    
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

    return relative_arrivals


def get_schema():

    scroll_speed = [
        schema.Option(display = "Slowest", value = "200"),
        schema.Option(display = "Slower", value = "150"),
        schema.Option(display = "Default", value = "100"),
        schema.Option(display = "Faster", value = "60"),
        schema.Option(display = "Fastest", value = "30"),
    ]

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
                name = "Route",
                desc = "Bus Route ID",
                icon = "bus",
                default = "40_100240", # 554E
            ),
            schema.Dropdown(
                id = "scroll_speed",
                name = "Scroll speed",
                desc = "Text scrolling speed",
                icon = "gaugeHigh",
                default = scroll_speed[2].value,
                options = scroll_speed,
            ),
        ],
    )
