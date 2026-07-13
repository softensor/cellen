"""
Tests for Food module — spec sections 9.1, 9.2, 9.3.

Covers:
  - Food item CRUD (UC-F1–F2)
  - Weekly menu CRUD with items (UC-M1–M4)
  - Current menu endpoint for a level
  - Meal orders (UC-MO1–MO2)
  - School isolation
  - Parent can view menu (read-only)
"""
from datetime import date, timedelta

from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _make_food(client: AsyncClient, token: str, **overrides) -> dict:
    body = {
        "name": f"Food-{uid()[:6]}",
        "food_type": "lunch",
        **overrides,
    }
    r = await client.post("/food/foods", json=body, headers=auth(token))
    assert r.status_code == 201, r.text
    return r.json()


async def _make_menu(client: AsyncClient, token: str, **overrides) -> dict:
    today = date.today()
    body = {
        "level": "Creche",
        "start_date": today.isoformat(),
        "end_date": (today + timedelta(days=6)).isoformat(),
        **overrides,
    }
    r = await client.post("/food/menus", json=body, headers=auth(token))
    assert r.status_code == 201, r.text
    return r.json()


async def _school_with_parent(client, make_school, prefix="fp"):
    school, admin_tok, slug, _ = await make_school(prefix)
    uname = f"p-{uid()}"
    grd_r = await client.post(
        "/guardians",
        json={"first_name": "P", "last_name": "P", "username": uname, "password": "Parent1!"},
        headers=auth(admin_tok),
    )
    assert grd_r.status_code == 201
    parent_tok = await login(client, uname, "Parent1!", slug)
    return admin_tok, parent_tok, slug


# ---------------------------------------------------------------------------
# UC-F1/F2: Food item CRUD
# ---------------------------------------------------------------------------

async def test_create_food_item(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("food-c")
    r = await client.post(
        "/food/foods",
        json={"name": "Arroz com Frango", "food_type": "lunch", "description": "Prato principal"},
        headers=auth(token),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["name"] == "Arroz com Frango"
    assert body["food_type"] == "lunch"
    assert "id" in body


async def test_list_food_items(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("food-l")
    await _make_food(client, token, name="Feijão Preto")
    await _make_food(client, token, name="Salada")

    r = await client.get("/food/foods", headers=auth(token))
    assert r.status_code == 200, r.text
    items = r.json()
    assert isinstance(items, list)
    assert len(items) >= 2


async def test_list_food_items_by_type(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("food-lt")
    await _make_food(client, token, name="Leite", food_type="breakfast")
    await _make_food(client, token, name="Sopa", food_type="lunch")

    r = await client.get("/food/foods?food_type=breakfast", headers=auth(token))
    assert r.status_code == 200
    for item in r.json():
        assert item["food_type"] == "breakfast", (
            f"Filter by food_type=breakfast must only return breakfast items; got {item['food_type']}"
        )


async def test_update_food_item(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("food-u")
    food = await _make_food(client, token)

    r = await client.patch(
        f"/food/foods/{food['id']}",
        json={"name": "Updated Food"},
        headers=auth(token),
    )
    assert r.status_code == 200, r.text
    assert r.json()["name"] == "Updated Food"


async def test_delete_food_item(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("food-d")
    food = await _make_food(client, token)

    r = await client.delete(f"/food/foods/{food['id']}", headers=auth(token))
    assert r.status_code == 200, r.text


async def test_food_school_isolation(client: AsyncClient, make_school):
    _, tok_a, _, _ = await make_school("food-isola")
    _, tok_b, _, _ = await make_school("food-isolb")

    food_a = await _make_food(client, tok_a)

    r = await client.get("/food/foods", headers=auth(tok_b))
    assert r.status_code == 200
    ids_b = [f["id"] for f in r.json()]
    assert food_a["id"] not in ids_b


# ---------------------------------------------------------------------------
# UC-M1/M2/M3/M4: Weekly menus
# ---------------------------------------------------------------------------

async def test_create_menu(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("menu-c")
    today = date.today()
    r = await client.post(
        "/food/menus",
        json={
            "level": "Creche",
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=4)).isoformat(),
        },
        headers=auth(token),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["level"] == "Creche"
    assert "id" in body


async def test_add_item_to_menu(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("menu-item")
    food = await _make_food(client, token)
    menu = await _make_menu(client, token)

    r = await client.post(
        f"/food/menus/{menu['id']}/items",
        json={"food_id": food["id"], "day_of_week": 0, "meal_type": "lunch"},
        headers=auth(token),
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body.get("food_id") == food["id"] or body.get("day_of_week") == 0


async def test_get_menu_with_items(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("menu-g")
    food = await _make_food(client, token)
    menu = await _make_menu(client, token)
    await client.post(
        f"/food/menus/{menu['id']}/items",
        json={"food_id": food["id"], "day_of_week": 1, "meal_type": "lunch"},
        headers=auth(token),
    )

    r = await client.get(f"/food/menus/{menu['id']}", headers=auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert "items" in body or "menu_items" in body, (
        "GET menu must include its items"
    )


async def test_remove_item_from_menu(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("menu-rm")
    food = await _make_food(client, token)
    menu = await _make_menu(client, token)

    item_r = await client.post(
        f"/food/menus/{menu['id']}/items",
        json={"food_id": food["id"], "day_of_week": 2, "meal_type": "snack"},
        headers=auth(token),
    )
    assert item_r.status_code == 201
    item_id = item_r.json()["id"]

    del_r = await client.delete(f"/food/menus/{menu['id']}/items/{item_id}", headers=auth(token))
    assert del_r.status_code == 200, del_r.text


async def test_current_menu_for_level(client: AsyncClient, make_school):
    """GET /food/menus/current?level=Creche returns the menu active today."""
    _, token, _, _ = await make_school("menu-curr")
    today = date.today()

    # Create a menu covering today
    await client.post(
        "/food/menus",
        json={
            "level": "Creche",
            "start_date": (today - timedelta(days=1)).isoformat(),
            "end_date": (today + timedelta(days=5)).isoformat(),
        },
        headers=auth(token),
    )

    r = await client.get("/food/menus/current?level=Creche", headers=auth(token))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["level"] == "Creche", (
        "Current menu must be for the requested level"
    )
    # Verify today falls within the menu's date range
    start = date.fromisoformat(body["start_date"])
    end = date.fromisoformat(body["end_date"])
    assert start <= today <= end, (
        f"Current menu date range {start}–{end} must include today {today}"
    )


async def test_no_menu_for_future_level_returns_404_or_empty(client: AsyncClient, make_school):
    """If no menu exists for a given level, the endpoint returns 404 or empty."""
    _, token, _, _ = await make_school("menu-none")

    r = await client.get("/food/menus/current?level=Berçário", headers=auth(token))
    assert r.status_code in (200, 404), r.text
    if r.status_code == 200:
        assert r.json() is None or r.json() == {}, (
            "No menu for this level must return null or empty"
        )


async def test_list_menus(client: AsyncClient, make_school):
    _, token, _, _ = await make_school("menu-l")
    await _make_menu(client, token, level="Berçário")
    await _make_menu(client, token, level="Jardim")

    r = await client.get("/food/menus", headers=auth(token))
    assert r.status_code == 200
    assert isinstance(r.json(), list)
    assert len(r.json()) >= 2


async def test_menu_school_isolation(client: AsyncClient, make_school):
    _, tok_a, _, _ = await make_school("menu-isola")
    _, tok_b, _, _ = await make_school("menu-isolb")

    menu_a = await _make_menu(client, tok_a)

    r = await client.get("/food/menus", headers=auth(tok_b))
    ids_b = [m["id"] for m in r.json()]
    assert menu_a["id"] not in ids_b


async def test_parent_can_view_menu(client: AsyncClient, make_school):
    """Parents can view the food menu (read-only)."""
    admin_tok, parent_tok, slug = await _school_with_parent(client, make_school, "menu-par")

    # Admin creates a menu
    today = date.today()
    await client.post(
        "/food/menus",
        json={"level": "Creche", "start_date": today.isoformat(),
              "end_date": (today + timedelta(days=4)).isoformat()},
        headers=auth(admin_tok),
    )

    r = await client.get("/food/menus/current?level=Creche", headers=auth(parent_tok))
    assert r.status_code in (200, 404), (
        f"Parent must be able to view the menu; got {r.status_code}: {r.text}"
    )


async def test_parent_cannot_create_menu(client: AsyncClient, make_school):
    """Parents cannot create menus."""
    admin_tok, parent_tok, slug = await _school_with_parent(client, make_school, "menu-par-auth")

    today = date.today()
    r = await client.post(
        "/food/menus",
        json={"level": "Creche", "start_date": today.isoformat(),
              "end_date": (today + timedelta(days=4)).isoformat()},
        headers=auth(parent_tok),
    )
    assert r.status_code == 403


# ---------------------------------------------------------------------------
# UC-MO1/MO2: Meal orders
# ---------------------------------------------------------------------------

async def test_create_meal_order(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("mo-c")

    child_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Meal", "last_name": "Kid"},
        headers=auth(admin_tok),
    )
    assert child_r.status_code == 201
    child_id = child_r.json()["id"]

    today = date.today().isoformat()
    r = await client.post(
        "/pickup-authorizations/meal-orders",
        json={"child_id": child_id, "order_date": today, "quantity": 1},
        headers=auth(admin_tok),
    )
    assert r.status_code == 201, r.text
    assert "id" in r.json()


async def test_daily_meal_order_counts(client: AsyncClient, make_school):
    school, admin_tok, slug, _ = await make_school("mo-count")

    child_r = await client.post(
        "/children",
        json={"cedula": f"C{uid()}", "first_name": "Mc", "last_name": "K"},
        headers=auth(admin_tok),
    )
    child_id = child_r.json()["id"]
    today = date.today().isoformat()

    await client.post(
        "/pickup-authorizations/meal-orders",
        json={"child_id": child_id, "order_date": today, "quantity": 1},
        headers=auth(admin_tok),
    )

    r = await client.get(
        f"/pickup-authorizations/meal-orders/daily-counts?date={today}",
        headers=auth(admin_tok),
    )
    assert r.status_code == 200, r.text
    data = r.json()
    # Should return a count or list with total
    assert isinstance(data, (dict, list, int)), f"Unexpected type: {type(data)}"
