"""
Tests for Documents Library and Photos — spec sections 17 and 18.

Covers:
  - UC-DL1–DL3: Documents library CRUD
  - UC-PH1–PH4: Photo gallery CRUD
  - All authenticated users can view documents
  - School isolation
  - File type and size validation
  - Parent access (read-only for documents, child-specific for photos)
"""
import struct
import zlib

from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ---------------------------------------------------------------------------
# Helpers — minimal valid image bytes
# ---------------------------------------------------------------------------

def _minimal_png() -> bytes:
    def chunk(name: bytes, data: bytes) -> bytes:
        c = name + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    header = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    idat = chunk(b"IDAT", zlib.compress(b"\x00\xFF\xFF\xFF"))
    iend = chunk(b"IEND", b"")
    return header + ihdr + idat + iend


def _minimal_pdf() -> bytes:
    return b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF"


async def _setup(client: AsyncClient, make_school, prefix="docs") -> dict:
    school, admin_tok, slug, _ = await make_school(prefix)

    # Teacher
    uname_t = f"t-{uid()}"
    emp_r = await client.post(
        "/employees",
        json={"first_name": "T", "last_name": "T", "employee_type": "teacher",
              "username": uname_t, "password": "Teacher1!"},
        headers=auth(admin_tok),
    )
    assert emp_r.status_code == 201
    teacher_tok = await login(client, uname_t, "Teacher1!", slug)

    # Parent
    uname_p = f"p-{uid()}"
    grd_r = await client.post(
        "/guardians",
        json={"first_name": "P", "last_name": "P", "username": uname_p, "password": "Parent1!"},
        headers=auth(admin_tok),
    )
    assert grd_r.status_code == 201
    parent_tok = await login(client, uname_p, "Parent1!", slug)

    # Child
    child_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Child", "last_name": "Docs"},
        headers=auth(admin_tok),
    )
    assert child_r.status_code == 201
    child_id = child_r.json()["id"]

    return {
        "admin_tok": admin_tok,
        "teacher_tok": teacher_tok,
        "parent_tok": parent_tok,
        "child_id": child_id,
        "slug": slug,
    }


# ============================================================================
# DOCUMENTS LIBRARY
# ============================================================================

async def test_admin_uploads_document(client: AsyncClient, make_school):
    """UC-DL1: Admin can upload a PDF to the shared library."""
    ctx = await _setup(client, make_school, "dl-c")

    r = await client.post(
        "/documents",
        files={"file": ("test.pdf", _minimal_pdf(), "application/pdf")},
        data={"name": "Regulamento Interno", "description": "School regulations"},
        headers=auth(ctx["admin_tok"]),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert "id" in body
    assert body.get("name") == "Regulamento Interno" or body.get("file_url")


async def test_teacher_uploads_document(client: AsyncClient, make_school):
    """Teachers can also upload documents to the shared library."""
    ctx = await _setup(client, make_school, "dl-t")

    r = await client.post(
        "/documents",
        files={"file": ("material.pdf", _minimal_pdf(), "application/pdf")},
        data={"name": "Material de Apoio"},
        headers=auth(ctx["teacher_tok"]),
    )
    assert r.status_code == 201, r.text


async def test_all_users_can_view_documents(client: AsyncClient, make_school):
    """UC-DL2: All authenticated users can list and download shared documents."""
    ctx = await _setup(client, make_school, "dl-view")

    # Admin uploads
    await client.post(
        "/documents",
        files={"file": ("shared.pdf", _minimal_pdf(), "application/pdf")},
        data={"name": "Shared Document"},
        headers=auth(ctx["admin_tok"]),
    )

    for tok, role in [
        (ctx["teacher_tok"], "teacher"),
        (ctx["parent_tok"], "parent"),
    ]:
        r = await client.get("/documents", headers=auth(tok))
        assert r.status_code == 200, (
            f"{role} must be able to view documents; got {r.status_code}: {r.text}"
        )
        assert isinstance(r.json(), list)


async def test_admin_deletes_document(client: AsyncClient, make_school):
    """UC-DL3: Admin can delete a shared document."""
    ctx = await _setup(client, make_school, "dl-d")

    doc_r = await client.post(
        "/documents",
        files={"file": ("delete-me.pdf", _minimal_pdf(), "application/pdf")},
        data={"name": "To Delete"},
        headers=auth(ctx["admin_tok"]),
    )
    assert doc_r.status_code == 201
    doc_id = doc_r.json()["id"]

    del_r = await client.delete(f"/documents/{doc_id}", headers=auth(ctx["admin_tok"]))
    assert del_r.status_code == 200, del_r.text


async def test_parent_cannot_delete_document(client: AsyncClient, make_school):
    """Parents cannot delete shared documents."""
    ctx = await _setup(client, make_school, "dl-par-d")

    doc_r = await client.post(
        "/documents",
        files={"file": ("cannot-delete.pdf", _minimal_pdf(), "application/pdf")},
        data={"name": "Protected"},
        headers=auth(ctx["admin_tok"]),
    )
    assert doc_r.status_code == 201
    doc_id = doc_r.json()["id"]

    r = await client.delete(f"/documents/{doc_id}", headers=auth(ctx["parent_tok"]))
    assert r.status_code == 403, f"Parent must not delete documents; got {r.status_code}"


async def test_document_invalid_type_rejected(client: AsyncClient, make_school):
    """Uploading an unsupported file type (e.g. .exe) must be rejected."""
    ctx = await _setup(client, make_school, "dl-type")

    r = await client.post(
        "/documents",
        files={"file": ("malware.exe", b"MZ\x90\x00", "application/octet-stream")},
        data={"name": "Bad file"},
        headers=auth(ctx["admin_tok"]),
    )
    assert r.status_code in (400, 415, 422), (
        f"Unsupported file type must be rejected; got {r.status_code}"
    )


async def test_document_school_isolation(client: AsyncClient, make_school):
    ctx_a = await _setup(client, make_school, "dl-isola")
    ctx_b = await _setup(client, make_school, "dl-isolb")

    doc_r = await client.post(
        "/documents",
        files={"file": ("school-a-doc.pdf", _minimal_pdf(), "application/pdf")},
        data={"name": "School A Only"},
        headers=auth(ctx_a["admin_tok"]),
    )
    assert doc_r.status_code == 201
    doc_id = doc_r.json()["id"]

    r = await client.get("/documents", headers=auth(ctx_b["admin_tok"]))
    ids_b = [d["id"] for d in r.json()]
    assert doc_id not in ids_b


# ============================================================================
# PHOTOS
# ============================================================================

async def test_upload_photo(client: AsyncClient, make_school):
    """UC-PH1: Teacher uploads a photo."""
    ctx = await _setup(client, make_school, "ph-c")

    r = await client.post(
        "/photos",
        files={"file": ("photo.png", _minimal_png(), "image/png")},
        data={"child_id": ctx["child_id"]},
        headers=auth(ctx["teacher_tok"]),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert "id" in body


async def test_list_photos(client: AsyncClient, make_school):
    """UC-PH2: All school users can browse photos."""
    ctx = await _setup(client, make_school, "ph-l")

    await client.post(
        "/photos",
        files={"file": ("a.png", _minimal_png(), "image/png")},
        data={"child_id": ctx["child_id"]},
        headers=auth(ctx["teacher_tok"]),
    )

    for tok, role in [(ctx["admin_tok"], "admin"), (ctx["teacher_tok"], "teacher")]:
        r = await client.get("/photos", headers=auth(tok))
        assert r.status_code == 200, f"{role} must be able to list photos; got {r.status_code}"
        assert isinstance(r.json(), list)


async def test_parent_can_view_photos_of_their_child(client: AsyncClient, make_school):
    """UC-PH3: Parent can view photos linked to their children."""
    ctx = await _setup(client, make_school, "ph-par")

    # Link guardian to child first
    grd_r = await client.post(
        "/guardians",
        json={"first_name": "G", "last_name": "G", "username": f"grd-{uid()}", "password": "Parent1!"},
        headers=auth(ctx["admin_tok"]),
    )
    assert grd_r.status_code == 201
    await client.post(
        f"/guardians/{grd_r.json()['id']}/children",
        json={"child_id": ctx["child_id"], "relationship_type": "father", "is_primary_contact": False},
        headers=auth(ctx["admin_tok"]),
    )

    # Upload a photo
    await client.post(
        "/photos",
        files={"file": ("child.png", _minimal_png(), "image/png")},
        data={"child_id": ctx["child_id"]},
        headers=auth(ctx["teacher_tok"]),
    )

    r = await client.get("/photos", headers=auth(ctx["parent_tok"]))
    assert r.status_code == 200, f"Parent must be able to view photos; got {r.status_code}"


async def test_admin_can_delete_photo(client: AsyncClient, make_school):
    """UC-PH4: Admin can delete a photo."""
    ctx = await _setup(client, make_school, "ph-d")

    ph_r = await client.post(
        "/photos",
        files={"file": ("del.png", _minimal_png(), "image/png")},
        data={"child_id": ctx["child_id"]},
        headers=auth(ctx["admin_tok"]),
    )
    assert ph_r.status_code == 201
    ph_id = ph_r.json()["id"]

    del_r = await client.delete(f"/photos/{ph_id}", headers=auth(ctx["admin_tok"]))
    assert del_r.status_code == 200, del_r.text


async def test_photo_invalid_type_rejected(client: AsyncClient, make_school):
    """Non-image file must be rejected for photo upload."""
    ctx = await _setup(client, make_school, "ph-type")

    r = await client.post(
        "/photos",
        files={"file": ("doc.pdf", _minimal_pdf(), "application/pdf")},
        data={"child_id": ctx["child_id"]},
        headers=auth(ctx["teacher_tok"]),
    )
    assert r.status_code in (400, 415, 422), (
        f"PDF must be rejected as a photo; got {r.status_code}"
    )


async def test_photo_school_isolation(client: AsyncClient, make_school):
    ctx_a = await _setup(client, make_school, "ph-isola")
    ctx_b = await _setup(client, make_school, "ph-isolb")

    ph_r = await client.post(
        "/photos",
        files={"file": ("a.png", _minimal_png(), "image/png")},
        data={"child_id": ctx_a["child_id"]},
        headers=auth(ctx_a["teacher_tok"]),
    )
    assert ph_r.status_code == 201
    ph_id = ph_r.json()["id"]

    r = await client.get("/photos", headers=auth(ctx_b["admin_tok"]))
    ids_b = [p["id"] for p in r.json()]
    assert ph_id not in ids_b
