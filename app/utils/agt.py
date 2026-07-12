import hashlib
from datetime import date


def generate_document_number(doc_type: str, year: int, number: int) -> str:
    """Generate AGT document number: 'FT 2024/0001'"""
    return f"{doc_type} {year}/{str(number).zfill(4)}"


def compute_hash(
    doc_number: str,
    doc_date: date,
    nif_emitter: str,
    nif_client: str,
    total: float,
    prev_hash: str,
) -> str:
    """Simplified AGT document hash chain"""
    data = f"{doc_number};{doc_date.isoformat()};{nif_emitter};{nif_client};{total:.2f};{prev_hash}"
    return hashlib.sha256(data.encode()).hexdigest()


async def get_last_document_hash(db, school_id, model_class) -> str:
    """Get hash_code of the most recent document of this type for chain linking."""
    from sqlalchemy import desc, select
    result = await db.execute(
        select(model_class.hash_code)
        .where(model_class.school_id == school_id)
        .order_by(desc(model_class.series_number))
        .limit(1)
    )
    row = result.scalar_one_or_none()
    return row or ""


async def get_next_series_number(db, school_id, doc_type: str, year: int) -> int:
    """Atomically get and increment next number for document series"""
    from sqlalchemy import select

    from app.models.modern import DocumentSeries

    result = await db.execute(
        select(DocumentSeries)
        .where(
            DocumentSeries.school_id == school_id,
            DocumentSeries.document_type == doc_type,
            DocumentSeries.year == year,
        )
        .with_for_update()
    )
    series = result.scalar_one_or_none()
    if series is None:
        series = DocumentSeries(
            school_id=school_id,
            document_type=doc_type,
            year=year,
            next_number=2,  # we'll use 1, so start at 2 for next
        )
        db.add(series)
        await db.flush()
        number = 1
    else:
        number = series.next_number
        series.next_number += 1
    return number
