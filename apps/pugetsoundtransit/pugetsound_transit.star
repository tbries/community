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
load("math.star", "math")
load("encoding/json.star", "json")

API_KEY = "" # TODO: Encrpt this.
API_BASE = "https://api.pugetsound.onebusaway.org/api"
API_ARRIVALS_AND_DEPARTURES = API_BASE + "/where/arrivals-and-departures-for-stop/%s.json"
API_STOPS = API_BASE + "/where/stop/%s.json"
API_STOPS_FOR_LOCATION = API_BASE + "/where/stops-for-location.json"

DEFAULT_STOPID = "1_64561" # Issaquah Highlands Park & Ride, Bay 4
DEFAULT_ROUTEID = "40_100240" # 554 Express to Seattle

def main(config):

    # TODO: Decrypt API key.
    api_key = API_KEY

    scroll_speed_ms = config.get("scroll_speed")
    if scroll_speed_ms == None:
        scroll_speed_ms = 100
    else:
        scroll_speed_ms = int(scroll_speed_ms)

    stop_id = config.get("stop_id")
    if stop_id == None or stop_id == "":
        stop_id = DEFAULT_STOPID
    else:
        stop_info = json.decode(json.decode(stop_id)["value"])
        stop_id = stop_info["id"]

    route_id = config.get("route_id")
    if route_id == None or route_id == "":
        route_id = DEFAULT_ROUTEID

    # Call API to get predictions for the given stop
    arrival_info = get_arrival_info(stop_id, route_id, api_key)

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
                                    color=arrival_info["route_color"],
                                    diameter=14,
                                    child=render.Text(content=arrival_info["route_short_name"],font='tom-thumb'),
                                ),
                            pad = 1
                        ),
                        render.Column(
                            children = [
                                render.Marquee(
                                    child = render.Text(content=arrival_info["stop_name"]),
                                    width=48
                                ),
                                render.Marquee(
                                    child = render.Row(
                                        children = compute_arrival_texts(arrival_info["arrival_times"])
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


def get_arrival_info(stop_id, route_id, api_key):
    # Call OBA API to get predictions for the given stop.
    rep = http.get(
        url = API_ARRIVALS_AND_DEPARTURES % stop_id,
        params = {
            "key": api_key,
            "minutesBefore": "0",
            "minutesAfter": "120",
            "includeReferences": "true",
            "includeSituations": "false",
            "version": "2",
        },
        ttl_seconds = 180,
    )

    if rep.status_code != 200:
        fail("Predictions request failed with status ", rep.status_code)

    json_data = rep.json()

    stop_name = "UNKNOWN STOP"
    for stop in json_data["data"]["references"]["stops"]:
        if stop["id"] == stop_id:
            stop_name = stop["name"]

    route_short_name = "UNK"
    route_color = "#333333"
    for route in json_data["data"]["references"]["routes"]:
        if route["id"] == route_id:
            route_short_name = route["shortName"]
            route_color = route["color"] if route["color"] != "" else "#333333"

    arrival_times = []
    for bus in json_data["data"]["entry"]["arrivalsAndDepartures"]:

        # Skip buses with departures disabled, i.e. this will be the bus's last stop.
        if bus["departureEnabled"] == False:
            continue

        if bus["routeId"] == route_id:
            arrival_times.append(
                {
                    "predictedArrivalTime": bus["predictedArrivalTime"],
                    "scheduledArrivalTime": bus["scheduledArrivalTime"],
                }
            )

    return {
        "stop_name": stop_name,
        "route_short_name": route_short_name,
        "route_color": route_color,
        "arrival_times": arrival_times,
    }


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


def distance(stop, location):
    # Distance metric for sorting stops
    return math.pow(stop["lat"] - float(location["lat"]), 2) + math.pow(stop["lon"] - float(location["lng"]), 2)


def get_stops_for_location(location):

    # TODO: Decrypt API key.
    api_key = API_KEY
    loc = json.decode(location)

    rep = http.get(
        url = API_STOPS_FOR_LOCATION,
        params = {
            "key": api_key,
            "lat": str(loc["lat"]),#"47.543",
            "lon": str(loc["lng"]),#"-122.018",
            "version": "2",
            "includeReferences": "true",
        },
        ttl_seconds = 3600, # 1 hour cache since this data shouldn't change often.
    )

    if rep.status_code != 200:
        fail("Stops for location request failed with status ", rep.status_code)

    json_data = rep.json()
    stops = json_data["data"]["list"]
    routes = json_data["data"]["references"]["routes"]

    options = []

    for stop in sorted(stops, key = lambda x: distance(x, loc))[:20]:

        routes_for_stop = []
        for route in routes:
            if route["id"] in stop["routeIds"]:
                routes_for_stop.append({
                    "id": route["id"],
                    "shortName": route["shortName"],
                    "description": route["description"],
                })

        stop_info = {
            "id": stop["id"],
            "name": stop["name"],
            "routes": routes_for_stop,
        }

        options.append(
            schema.Option(display = stop["name"], value = json.encode(stop_info))
        )

    return options


def get_routes_for_stop(stop_id):

    stop_info = json.decode(json.decode(stop_id)["value"])
    options = []

    for route in stop_info["routes"]:
        display_text = "%s - %s" % (route["shortName"], route["description"])
        options.append(schema.Option(display = display_text, value = route["id"]))

    return [
        schema.Dropdown(
            id = "route_id",
            name = "Route",
            desc = "Choose from routes that service this stop",
            # TODO: Choose an icon based on the stop type?
            icon = "bus",
            options = options,
            default = options[0].value,
        )]


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
            schema.Dropdown(
                id = "scroll_speed",
                name = "Scroll speed",
                desc = "Text scrolling speed",
                icon = "gaugeHigh",
                default = scroll_speed[2].value,
                options = scroll_speed,
            ),
            schema.LocationBased(
                id = "stop_id",
                name = "Bus Stop",
                desc = "Choose from the 20 nearest stops",
                icon = "bus",
                handler = get_stops_for_location,
            ),
            schema.Generated(
                id = "routes_for_stop",
                source = "stop_id",
                handler = get_routes_for_stop,
            ),
        ],
    )
