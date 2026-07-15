import uuid
from pathlib import Path

from fastapi import HTTPException, UploadFile

from app.core.config import settings

ALLOWED_CONTENT_TYPES = {
    "image/jpeg", "image/png", "image/webp", "image/gif",
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB


async def save_upload(
    file: UploadFile, entity_type: str, entity_id: uuid.UUID,
    content_type_override: str | None = None,
) -> str:
    """
    Save file to MEDIA_DIR/{entity_type}/{entity_id}/{filename}
    Returns relative URL path.
    Validates: max 5MB, allowed types: image/jpeg, image/png, application/pdf
    """
    effective_content_type = content_type_override or file.content_type
    if effective_content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"File type '{effective_content_type}' not allowed. Allowed: {', '.join(ALLOWED_CONTENT_TYPES)}",
        )

    content = await file.read()
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=400,
            detail="File too large. Maximum size is 5MB.",
        )

    # Build destination directory
    dest_dir = Path(settings.MEDIA_DIR) / entity_type / str(entity_id)
    dest_dir.mkdir(parents=True, exist_ok=True)

    # Sanitize filename and ensure unique
    original_name = file.filename or "upload"
    ext = Path(original_name).suffix.lower()
    if not ext:
        # Derive extension from content type
        ext_map = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "application/pdf": ".pdf"}
        ext = ext_map.get(file.content_type, "")
    safe_name = f"{uuid.uuid4()}{ext}"
    dest_path = dest_dir / safe_name

    with open(dest_path, "wb") as f:
        f.write(content)

    relative_url = f"/media/{entity_type}/{entity_id}/{safe_name}"
    return relative_url


async def delete_file(url: str) -> None:
    """Delete a file given its relative URL path."""
    if not url:
        return
    # Strip leading slash
    relative = url.lstrip("/")
    # relative is like "media/entity_type/entity_id/filename"
    # relative is "media/entity_type/entity_id/filename" — strip the "media/" prefix
    full_path = Path(settings.MEDIA_DIR) / relative.removeprefix("media/").removeprefix("media\\")
    if full_path.exists():
        full_path.unlink()
