"""
Shared Pydantic building blocks.

DecimalFloat: use instead of Decimal in any schema field that is sent to the
Flutter client.  Pydantic v2 serialises plain `Decimal` as a JSON *string*
("12.00") which causes Flutter TypeErrors.  This annotated type serialises to
a JSON *number* (12.0) while keeping Decimal validation on the way in.
"""
from decimal import Decimal
from typing import Annotated

from pydantic.functional_serializers import PlainSerializer

DecimalFloat = Annotated[
    Decimal,
    PlainSerializer(
        lambda v: float(v) if v is not None else None,
        return_type=float,
        when_used="json",
    ),
]
