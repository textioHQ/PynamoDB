"""
Utils
"""
import json
import re
from typing import Any
from typing import Dict

from pynamodb.constants import BINARY
from pynamodb.constants import BINARY_SET
from pynamodb.constants import BOOLEAN
from pynamodb.constants import LIST
from pynamodb.constants import MAP
from pynamodb.constants import NULL
from pynamodb.constants import NUMBER
from pynamodb.constants import NUMBER_SET
from pynamodb.constants import STRING
from pynamodb.constants import STRING_SET


def attribute_value_to_json(attribute_value: Dict[str, Any]) -> Any:
    attr_type, attr_value = next(iter(attribute_value.items()))
    if attr_type == LIST:
        return [attribute_value_to_json(v) for v in attr_value]
    if attr_type == MAP:
        return {k: attribute_value_to_json(v) for k, v in attr_value.items()}
    if attr_type == NULL:
        return None
    if attr_type in {BINARY, BINARY_SET, BOOLEAN, STRING, STRING_SET}:
        return attr_value
    if attr_type == NUMBER:
        return json.loads(attr_value)
    if attr_type == NUMBER_SET:
        return [json.loads(v) for v in attr_value]
    raise ValueError("Unknown attribute type: {}".format(attr_type))


def json_to_attribute_value(value: Any) -> Dict[str, Any]:
    if value is None:
        return {NULL: True}
    if value is True or value is False:
        return {BOOLEAN: value}
    if isinstance(value, (int, float)):
        return {NUMBER: json.dumps(value)}
    if isinstance(value, str):
        return {STRING: value}
    if isinstance(value, list):
        return {LIST: [json_to_attribute_value(v) for v in value]}
    if isinstance(value, dict):
        return {MAP: {k: json_to_attribute_value(v) for k, v in value.items()}}
    raise ValueError("Unknown value type: {}".format(type(value).__name__))


def snake_to_camel_case(var_name: str) -> str:
    """
    Converts camel case variable names to snake case variable_names
    """
    first_pass = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', var_name)
    return re.sub('([a-z0-9])([A-Z])', r'\1_\2', first_pass).lower()
