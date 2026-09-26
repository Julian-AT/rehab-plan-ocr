"""Strict experimental intent contract. This module never executes calendar changes.

Facts and user-facing answers are outside this model's output contract. References
must belong to the supplied visible-calendar context. Shipping integration must
still revalidate the calendar snapshot and require visible mutation confirmation.
"""

import datetime
import json
import re

DETAILS = {"next", "room", "therapist", "start", "end", "duration", "list", "count"}
TOPICS = {"capture", "calendars", "archive", "voice", "privacy"}
PROBLEMS = {
    "invalid_date",
    "ambiguous",
    "missing_date",
    "missing_time",
    "missing_title",
    "missing_event",
    "unsupported",
}


class InvalidIntent(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidIntent(message)


def object_keys(value, allowed, required=()):
    require(type(value) is dict, "Expected a JSON object")
    require(set(value) <= set(allowed), "Unknown fields are forbidden")
    require(set(required) <= set(value), "Required fields are missing")


def canonical_date(value):
    require(type(value) is str and re.fullmatch(r"\d{4}-\d{2}-\d{2}", value), "Invalid date format")
    try:
        datetime.date.fromisoformat(value)
    except ValueError as error:
        raise InvalidIntent("Invalid calendar date") from error


def canonical_time(value):
    require(
        type(value) is str and re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", value), "Invalid time"
    )


def validate(value, *, references=()):
    object_keys(value, {"action", "query", "change", "topic", "problem"}, {"action"})
    action = value["action"]
    require(type(action) is str, "Action must be a string")
    fields = {
        "calendar": {"action", "query"},
        "create": {"action", "change"},
        "update": {"action", "query", "change"},
        "remove": {"action", "query"},
        "cancel": {"action"},
        "help": {"action", "topic"},
        "clarify": {"action", "problem"},
    }
    require(action in fields, "Unknown action")
    require(set(value) == fields[action], "Action fields do not match its contract")
    if "query" in value:
        query = value["query"]
        if action == "calendar":
            object_keys(query, {"detail", "date", "reference", "after", "before"}, {"detail"})
            require(type(query["detail"]) is str and query["detail"] in DETAILS, "Unknown detail")
            require("date" in query or "reference" in query, "Query has no temporal or event scope")
        else:
            object_keys(query, {"reference"}, {"reference"})
        if "reference" in query:
            require(
                type(query["reference"]) is str and query["reference"] in references,
                "Unknown event reference",
            )
        if "date" in query:
            canonical_date(query["date"])
        for name in ["after", "before"]:
            if name in query:
                canonical_time(query[name])
        if "after" in query and "before" in query:
            require(query["after"] < query["before"], "Contradictory time bounds")
    if "change" in value:
        change = value["change"]
        required = {"title", "date", "time"} if action == "create" else set()
        object_keys(change, {"title", "date", "time", "duration"}, required)
        require(bool(change), "Empty change")
        if "title" in change:
            title = change["title"]
            require(
                type(title) is str and bool(title.strip()) and len(title) <= 200,
                "Missing or overlong title",
            )
        if "date" in change:
            canonical_date(change["date"])
        if "time" in change:
            canonical_time(change["time"])
        if "duration" in change:
            require(
                type(change["duration"]) is int and 1 <= change["duration"] <= 1440,
                "Invalid duration",
            )
    if action == "help":
        require(type(value["topic"]) is str and value["topic"] in TOPICS, "Unknown help topic")
    if action == "clarify":
        require(type(value["problem"]) is str and value["problem"] in PROBLEMS, "Unknown problem")
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "Duplicate JSON key")
        result[key] = value
    return result


def parse(text, *, references=()):
    require(isinstance(text, str) and len(text) <= 4096, "Missing or oversized output")
    # llama-completion's display marker is not part of the model's JSON response.
    clean = text.strip().removesuffix("[end of text]").rstrip()
    try:
        value = json.loads(clean, object_pairs_hook=unique_object)
    except (ValueError, RecursionError) as error:
        raise InvalidIntent(f"Invalid JSON: {error}") from error
    return validate(value, references=references)
