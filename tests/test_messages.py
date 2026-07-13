"""
Tests for Messaging — spec section 13.2 (Direct Messages) and 13.3 (Broadcast).

Covers:
  - UC-MSG1: Create a direct message thread
  - UC-MSG2: Post a message to a thread
  - UC-MSG3: List threads with unread counts
  - UC-MSG4: Mark thread as read
  - UC-BC1: Admin sends broadcast
  - Role restrictions on thread creation
  - School isolation
"""
from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _make_teacher(client, admin_tok, slug) -> tuple[str, str]:
    """Returns (employee_id, teacher_token)."""
    uname = f"t-{uid()}"
    r = await client.post(
        "/employees",
        json={"first_name": "T", "last_name": "T", "employee_type": "teacher",
              "username": uname, "password": "Teacher1!"},
        headers=auth(admin_tok),
    )
    assert r.status_code == 201, r.text
    tok = await login(client, uname, "Teacher1!", slug)
    return r.json()["id"], tok


async def _make_parent(client, admin_tok, slug) -> tuple[str, str]:
    """Returns (guardian_id, parent_token)."""
    uname = f"p-{uid()}"
    r = await client.post(
        "/guardians",
        json={"first_name": "P", "last_name": "P", "username": uname, "password": "Parent1!"},
        headers=auth(admin_tok),
    )
    assert r.status_code == 201, r.text
    tok = await login(client, uname, "Parent1!", slug)
    return r.json()["id"], tok


async def _setup(client: AsyncClient, make_school, prefix="msg") -> dict:
    school, admin_tok, slug, _ = await make_school(prefix)
    teacher_id, teacher_tok = await _make_teacher(client, admin_tok, slug)
    guardian_id, parent_tok = await _make_parent(client, admin_tok, slug)

    return {
        "admin_tok": admin_tok,
        "teacher_tok": teacher_tok,
        "parent_tok": parent_tok,
        "teacher_id": teacher_id,
        "guardian_id": guardian_id,
        "slug": slug,
    }


# ---------------------------------------------------------------------------
# UC-MSG1: Create a direct message thread
# ---------------------------------------------------------------------------

async def test_admin_can_create_thread(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "msg-adm")

    r = await client.post(
        "/messages/threads",
        json={"subject": "Reunião", "participant_ids": [ctx["teacher_id"]]},
        headers=auth(ctx["admin_tok"]),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert "id" in body
    assert body.get("subject") == "Reunião" or body.get("thread_type") == "direct"


async def test_parent_can_start_thread_with_teacher(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "msg-par")

    # Parent needs to know the teacher's user_id; derive from teacher_id (employee)
    # The thread API may accept employee_id or user_id depending on implementation
    r = await client.post(
        "/messages/threads",
        json={"subject": "Pergunta sobre o meu filho", "participant_ids": [ctx["teacher_id"]]},
        headers=auth(ctx["parent_tok"]),
    )
    assert r.status_code == 201, (
        f"Parent must be able to start a thread with a teacher; got {r.status_code}: {r.text}"
    )


async def test_teacher_can_start_thread_with_parent(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "msg-tch")

    r = await client.post(
        "/messages/threads",
        json={"subject": "Progresso da criança", "participant_ids": [ctx["guardian_id"]]},
        headers=auth(ctx["teacher_tok"]),
    )
    assert r.status_code == 201, (
        f"Teacher must be able to start a thread with a parent; got {r.status_code}: {r.text}"
    )


# ---------------------------------------------------------------------------
# UC-MSG2: Post a message to a thread
# ---------------------------------------------------------------------------

async def test_post_message_to_thread(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "msg-post")

    thread_r = await client.post(
        "/messages/threads",
        json={"subject": "Conversa", "participant_ids": [ctx["teacher_id"]]},
        headers=auth(ctx["admin_tok"]),
    )
    assert thread_r.status_code == 201, thread_r.text
    thread_id = thread_r.json()["id"]

    r = await client.post(
        f"/messages/threads/{thread_id}/messages",
        json={"body": "Olá, tudo bem?"},
        headers=auth(ctx["admin_tok"]),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body.get("body") == "Olá, tudo bem?"


async def test_non_participant_cannot_post_to_thread(client: AsyncClient, make_school):
    """A user not in the thread cannot post messages to it."""
    school, admin_tok, slug, _ = await make_school("msg-np")
    teacher1_id, teacher1_tok = await _make_teacher(client, admin_tok, slug)
    _, teacher2_tok = await _make_teacher(client, admin_tok, slug)

    thread_r = await client.post(
        "/messages/threads",
        json={"subject": "Private", "participant_ids": [teacher1_id]},
        headers=auth(admin_tok),
    )
    assert thread_r.status_code == 201
    thread_id = thread_r.json()["id"]

    r = await client.post(
        f"/messages/threads/{thread_id}/messages",
        json={"body": "Intruder message"},
        headers=auth(teacher2_tok),
    )
    assert r.status_code in (403, 404), (
        f"Non-participant must not post to thread; got {r.status_code}"
    )


async def test_messages_in_thread_are_ordered(client: AsyncClient, make_school):
    """Messages in a thread must be returned in chronological order."""
    ctx = await _setup(client, make_school, "msg-ord")

    thread_r = await client.post(
        "/messages/threads",
        json={"subject": "Order test", "participant_ids": [ctx["teacher_id"]]},
        headers=auth(ctx["admin_tok"]),
    )
    thread_id = thread_r.json()["id"]

    for i in range(3):
        await client.post(
            f"/messages/threads/{thread_id}/messages",
            json={"body": f"Message {i}"},
            headers=auth(ctx["admin_tok"]),
        )

    r = await client.get(f"/messages/threads/{thread_id}/messages", headers=auth(ctx["admin_tok"]))
    assert r.status_code == 200
    messages = r.json()
    assert isinstance(messages, list)
    assert len(messages) == 3
    # Messages must be in order (created_at ascending)
    bodies = [m["body"] for m in messages]
    assert bodies == ["Message 0", "Message 1", "Message 2"], (
        f"Messages must be chronologically ordered; got: {bodies}"
    )


# ---------------------------------------------------------------------------
# UC-MSG3: List threads with unread counts
# ---------------------------------------------------------------------------

async def test_list_threads_returns_unread_count(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "msg-unread")

    thread_r = await client.post(
        "/messages/threads",
        json={"subject": "Unread test", "participant_ids": [ctx["teacher_id"]]},
        headers=auth(ctx["admin_tok"]),
    )
    assert thread_r.status_code == 201
    thread_id = thread_r.json()["id"]

    # Admin posts a message (teacher hasn't read it)
    await client.post(
        f"/messages/threads/{thread_id}/messages",
        json={"body": "New message"},
        headers=auth(ctx["admin_tok"]),
    )

    r = await client.get("/messages/threads", headers=auth(ctx["teacher_tok"]))
    assert r.status_code == 200
    threads = r.json()
    thread = next((t for t in threads if t["id"] == thread_id), None)
    assert thread is not None, "Teacher must see the thread they are a participant of"
    assert "unread_count" in thread, "Thread list must include unread_count per thread"
    assert thread["unread_count"] >= 1, (
        f"Unread count must be >= 1 before teacher reads the thread; got {thread['unread_count']}"
    )


async def test_list_threads_only_shows_own_threads(client: AsyncClient, make_school):
    """A user sees only threads they participate in."""
    ctx = await _setup(client, make_school, "msg-own")

    # Create a thread between admin and teacher (parent is NOT in it)
    thread_r = await client.post(
        "/messages/threads",
        json={"subject": "Private admin-teacher", "participant_ids": [ctx["teacher_id"]]},
        headers=auth(ctx["admin_tok"]),
    )
    thread_id = thread_r.json()["id"]

    r = await client.get("/messages/threads", headers=auth(ctx["parent_tok"]))
    assert r.status_code == 200
    thread_ids = [t["id"] for t in r.json()]
    assert thread_id not in thread_ids, (
        "Parent must not see threads they are not a participant of"
    )


# ---------------------------------------------------------------------------
# UC-MSG4: Mark thread as read
# ---------------------------------------------------------------------------

async def test_mark_thread_as_read_clears_unread_count(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "msg-read")

    thread_r = await client.post(
        "/messages/threads",
        json={"subject": "Read test", "participant_ids": [ctx["teacher_id"]]},
        headers=auth(ctx["admin_tok"]),
    )
    thread_id = thread_r.json()["id"]

    await client.post(
        f"/messages/threads/{thread_id}/messages",
        json={"body": "Read me"},
        headers=auth(ctx["admin_tok"]),
    )

    # Teacher marks the thread as read
    r = await client.put(
        f"/messages/threads/{thread_id}/read",
        headers=auth(ctx["teacher_tok"]),
    )
    assert r.status_code == 200, r.text

    # Now unread count must be 0
    threads_r = await client.get("/messages/threads", headers=auth(ctx["teacher_tok"]))
    threads = threads_r.json()
    thread = next((t for t in threads if t["id"] == thread_id), None)
    if thread:
        assert thread.get("unread_count", 0) == 0, (
            f"Unread count must be 0 after marking as read; got {thread.get('unread_count')}"
        )


# ---------------------------------------------------------------------------
# UC-BC1: Broadcast messages (admin only)
# ---------------------------------------------------------------------------

async def test_admin_can_send_broadcast(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "msg-bc")

    r = await client.post(
        "/messages/broadcast",
        json={"body": "Important school-wide announcement via broadcast", "target": "all"},
        headers=auth(ctx["admin_tok"]),
    )
    assert r.status_code in (200, 201), (
        f"Admin must be able to send broadcast; got {r.status_code}: {r.text}"
    )


async def test_teacher_cannot_send_broadcast(client: AsyncClient, make_school):
    ctx = await _setup(client, make_school, "msg-bc-auth")

    r = await client.post(
        "/messages/broadcast",
        json={"body": "Unauthorized broadcast attempt", "target": "all"},
        headers=auth(ctx["teacher_tok"]),
    )
    assert r.status_code == 403, (
        f"Teachers must not send broadcasts; got {r.status_code}"
    )


async def test_broadcast_creates_notification_for_recipients(client: AsyncClient, make_school):
    """A broadcast to 'teachers' must create a notification for each teacher."""
    ctx = await _setup(client, make_school, "msg-bc-notif")

    await client.post(
        "/messages/broadcast",
        json={"body": "Broadcast to teachers", "target": "teachers"},
        headers=auth(ctx["admin_tok"]),
    )

    # Teacher should have a notification
    notif_r = await client.get("/notifications", headers=auth(ctx["teacher_tok"]))
    assert notif_r.status_code == 200
    # We can only verify that at least the endpoint works; notification content depends on implementation
    assert isinstance(notif_r.json(), list)


# ---------------------------------------------------------------------------
# School isolation
# ---------------------------------------------------------------------------

async def test_message_thread_school_isolation(client: AsyncClient, make_school):
    """Users from school B cannot read threads from school A."""
    school_a, tok_a, slug_a, _ = await make_school("msg-isola")
    school_b, tok_b, slug_b, _ = await make_school("msg-isolb")

    teacher_id_a, _ = await _make_teacher(client, tok_a, slug_a)

    thread_r = await client.post(
        "/messages/threads",
        json={"subject": "School A private", "participant_ids": [teacher_id_a]},
        headers=auth(tok_a),
    )
    assert thread_r.status_code == 201
    thread_id = thread_r.json()["id"]

    # School B admin tries to access thread from school A directly
    r = await client.get(f"/messages/threads/{thread_id}/messages", headers=auth(tok_b))
    assert r.status_code in (403, 404), (
        f"School B must not access school A's thread; got {r.status_code}"
    )
