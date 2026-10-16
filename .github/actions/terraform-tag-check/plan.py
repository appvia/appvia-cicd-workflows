"""Reads a terraform plan (terraform show -json) into the resources the tag policy applies to."""
import json
from dataclasses import dataclass, field


class PlanError(Exception):
    """The file is not a readable terraform plan."""


@dataclass(frozen=True)
class Resource:
    address: str
    type: str
    tags: dict = field(default_factory=dict)  # tags whose values are known now
    unknown_tags: frozenset = frozenset()  # tag keys only known after apply
    all_unknown: bool = False  # the whole tags attribute is only known after apply
    skip_reason: str = ""  # set when the tags cannot be checked at all

    def tag_unknown(self, key):
        if key in self.unknown_tags:
            return True
        return self.all_unknown and self.tags.get(key) in (None, "")


def load_plan(path):
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as err:
        raise PlanError(f"cannot read {path}: {err}") from err
    if not isinstance(data, dict):
        raise PlanError(f"{path} is not a terraform plan (expected a JSON object)")
    return data


def resources(plan, exclude_types=()):
    """Yields every managed resource being created or updated that has a tags attribute."""
    changes = plan.get("resource_changes")
    if changes is None:
        return
    if not isinstance(changes, list):
        raise PlanError("resource_changes is not a list, is this a terraform plan?")
    for entry in changes:
        if not isinstance(entry, dict) or entry.get("mode") != "managed":
            continue
        change = entry.get("change") or {}
        if not set(change.get("actions") or []) & {"create", "update"}:
            continue
        if entry.get("type") in exclude_types:
            continue
        after = change.get("after") or {}
        after_unknown = change.get("after_unknown") or {}
        attribute = _tag_attribute(after, after_unknown)
        if attribute is not None:
            yield _resource(entry, attribute, after, after_unknown)


# tags_all includes provider default_tags; unknown attributes are omitted from after
def _tag_attribute(after, after_unknown):
    for attribute in ("tags_all", "tags"):
        if attribute in after or attribute in after_unknown:
            return attribute
    return None


def _resource(entry, attribute, after, after_unknown):
    address = entry.get("address", "")
    rtype = entry.get("type", "")
    unknown = after_unknown.get(attribute) or False
    if unknown is True:
        # The keys may still come from default_tags, but known values in tags can be checked
        return Resource(address, rtype, _as_map(after.get("tags") or {}) or {}, all_unknown=True)
    tags = _as_map(after.get(attribute) or {})
    if tags is None:
        reason = f"{attribute} is not a map of tags, so it was not checked"
        return Resource(address, rtype, skip_reason=reason)
    unknown_tags = frozenset()
    if isinstance(unknown, dict):
        unknown_tags = frozenset(key for key, value in unknown.items() if value is True)
    return Resource(address, rtype, tags, unknown_tags)


# Tags as a map; providers such as awscc use a list of {key, value} objects. Anything else is None
def _as_map(value):
    if isinstance(value, dict):
        return value
    if isinstance(value, list) and all(isinstance(item, dict) for item in value):
        try:
            return {item["key"]: item["value"] for item in value}
        except KeyError:
            return None
    return None
