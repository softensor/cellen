"""
Tests for /employees and /guardians endpoints.
"""
from datetime import date

import pytest
from httpx import AsyncClient

from tests.conftest import auth, login, uid


# ---------------------------------------------------------------------------
# Employees
# ---------------------------------------------------------------------------

async def test_create_employee(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("emp")
    r = await client.post(
        "/employees",
        json={
            "first_name": "João",
            "last_name": "Ferreira",
            "employee_type": "teacher",
            "username": f"teacher-{uid()}",
            "password": "Teacher1!",
        },
        headers=auth(token),
    )
    assert r.status_code == 201
    data = r.json()
    assert "id" in data
    assert "school_id" in data


async def test_list_employees(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("empl")
    username = f"teacher-{uid()}"
    await client.post(
        "/employees",
        json={
            "first_name": "Ana",
            "last_name": "Costa",
            "employee_type": "teacher",
            "username": username,
            "password": "Teacher1!",
        },
        headers=auth(token),
    )
    r = await client.get("/employees", headers=auth(token))
    assert r.status_code == 200
    items = r.json()
    assert isinstance(items, list)
    assert any(e["first_name"] == "Ana" for e in items)


async def test_get_employee(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("empg")
    cr = await client.post(
        "/employees",
        json={
            "first_name": "Pedro",
            "last_name": "Lopes",
            "employee_type": "staff",
            "username": f"staff-{uid()}",
            "password": "Staff1234!",
        },
        headers=auth(token),
    )
    assert cr.status_code == 201
    emp_id = cr.json()["id"]
    r = await client.get(f"/employees/{emp_id}", headers=auth(token))
    assert r.status_code == 200
    assert r.json()["id"] == emp_id


async def test_update_employee(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("empu")
    cr = await client.post(
        "/employees",
        json={
            "first_name": "Carla",
            "last_name": "Neves",
            "employee_type": "admin",
            "username": f"admin-{uid()}",
            "password": "Admin1234!",
        },
        headers=auth(token),
    )
    assert cr.status_code == 201
    emp_id = cr.json()["id"]
    r = await client.patch(
        f"/employees/{emp_id}",
        json={"position": "Director"},
        headers=auth(token),
    )
    assert r.status_code == 200
    assert r.json()["position"] == "Director"


async def test_employee_salary_is_number(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("empsal")
    cr = await client.post(
        "/employees",
        json={
            "first_name": "Sara",
            "last_name": "Dias",
            "employee_type": "teacher",
            "username": f"teacher-{uid()}",
            "password": "Teacher1!",
            "salary": 1500.50,
        },
        headers=auth(token),
    )
    assert cr.status_code == 201
    emp_id = cr.json()["id"]
    r = await client.get(f"/employees/{emp_id}", headers=auth(token))
    assert r.status_code == 200
    salary = r.json()["salary"]
    assert salary is not None
    assert isinstance(salary, (int, float))


async def test_employee_height_is_number(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("emph")
    cr = await client.post(
        "/employees",
        json={
            "first_name": "Rui",
            "last_name": "Gomes",
            "employee_type": "staff",
            "username": f"staff-{uid()}",
            "password": "Staff1234!",
            "height": 1.75,
        },
        headers=auth(token),
    )
    assert cr.status_code == 201
    emp_id = cr.json()["id"]
    r = await client.get(f"/employees/{emp_id}", headers=auth(token))
    assert r.status_code == 200
    height = r.json()["height"]
    assert height is not None
    assert isinstance(height, (int, float))


async def test_set_employee_password(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("emppw")
    username = f"teacher-{uid()}"
    cr = await client.post(
        "/employees",
        json={
            "first_name": "Luis",
            "last_name": "Marques",
            "employee_type": "teacher",
            "username": username,
            "password": "OldPass1!",
        },
        headers=auth(token),
    )
    assert cr.status_code == 201
    emp_id = cr.json()["id"]

    r = await client.patch(
        f"/employees/{emp_id}/set-password",
        json={"password": "NewPass1!"},
        headers=auth(token),
    )
    assert r.status_code == 200

    # Login with the new password must succeed
    login_r = await client.post(
        "/auth/login",
        json={"username": username, "password": "NewPass1!", "school_slug": slug},
    )
    assert login_r.status_code == 200


async def test_delete_employee(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("empd")
    cr = await client.post(
        "/employees",
        json={
            "first_name": "Maria",
            "last_name": "Santos",
            "employee_type": "staff",
            "username": f"staff-{uid()}",
            "password": "Staff1234!",
        },
        headers=auth(token),
    )
    assert cr.status_code == 201
    emp_id = cr.json()["id"]

    dr = await client.delete(f"/employees/{emp_id}", headers=auth(token))
    assert dr.status_code == 200

    # Delete is a soft-delete (sets status="inactive"); record still exists
    gr = await client.get(f"/employees/{emp_id}", headers=auth(token))
    assert gr.status_code == 200
    assert gr.json()["status"] == "inactive"


async def test_employee_school_isolation(client: AsyncClient, make_school):
    school_a, token_a, slug_a, _ = await make_school("isola")
    school_b, token_b, slug_b, _ = await make_school("isolb")

    cr = await client.post(
        "/employees",
        json={
            "first_name": "School",
            "last_name": "ATeacher",
            "employee_type": "teacher",
            "username": f"teacher-{uid()}",
            "password": "Teacher1!",
        },
        headers=auth(token_a),
    )
    assert cr.status_code == 201
    emp_id = cr.json()["id"]

    # School B admin tries to access school A's employee — must get 404
    r = await client.get(f"/employees/{emp_id}", headers=auth(token_b))
    assert r.status_code == 404


async def test_teacher_cannot_create_employee(client: AsyncClient, make_school):
    school, admin_token, slug, _ = await make_school("empforbid")

    # Create a teacher
    teacher_username = f"teacher-{uid()}"
    cr = await client.post(
        "/employees",
        json={
            "first_name": "Forbidden",
            "last_name": "Teacher",
            "employee_type": "teacher",
            "username": teacher_username,
            "password": "Teacher1!",
        },
        headers=auth(admin_token),
    )
    assert cr.status_code == 201

    teacher_token = await login(client, teacher_username, "Teacher1!", slug)

    # Teacher tries to create another employee — must get 403
    r = await client.post(
        "/employees",
        json={
            "first_name": "Another",
            "last_name": "Employee",
            "employee_type": "staff",
            "username": f"staff-{uid()}",
            "password": "Staff1234!",
        },
        headers=auth(teacher_token),
    )
    assert r.status_code == 403


# ---------------------------------------------------------------------------
# Guardians
# ---------------------------------------------------------------------------

async def test_create_guardian(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("grd")
    r = await client.post(
        "/guardians",
        json={
            "first_name": "Rosa",
            "last_name": "Almeida",
            "username": f"parent-{uid()}",
            "password": "Parent1!",
        },
        headers=auth(token),
    )
    assert r.status_code == 201
    data = r.json()
    assert "id" in data


async def test_list_guardians(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("grdl")
    await client.post(
        "/guardians",
        json={
            "first_name": "José",
            "last_name": "Lima",
            "username": f"parent-{uid()}",
            "password": "Parent1!",
        },
        headers=auth(token),
    )
    r = await client.get("/guardians", headers=auth(token))
    assert r.status_code == 200
    assert isinstance(r.json(), list)


async def test_get_guardian(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("grdg")
    cr = await client.post(
        "/guardians",
        json={
            "first_name": "Filipa",
            "last_name": "Ramos",
            "username": f"parent-{uid()}",
            "password": "Parent1!",
        },
        headers=auth(token),
    )
    assert cr.status_code == 201
    grd_id = cr.json()["id"]
    r = await client.get(f"/guardians/{grd_id}", headers=auth(token))
    assert r.status_code == 200
    assert r.json()["id"] == grd_id


async def test_update_guardian(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("grdu")
    cr = await client.post(
        "/guardians",
        json={
            "first_name": "Sofia",
            "last_name": "Pinto",
            "username": f"parent-{uid()}",
            "password": "Parent1!",
        },
        headers=auth(token),
    )
    assert cr.status_code == 201
    grd_id = cr.json()["id"]
    r = await client.patch(
        f"/guardians/{grd_id}",
        json={"mobile_first": "912345678"},
        headers=auth(token),
    )
    assert r.status_code == 200
    assert r.json()["mobile_first"] == "912345678"


async def test_set_guardian_password(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("grdpw")
    username = f"parent-{uid()}"
    cr = await client.post(
        "/guardians",
        json={
            "first_name": "Beatriz",
            "last_name": "Sousa",
            "username": username,
            "password": "OldParent1!",
        },
        headers=auth(token),
    )
    assert cr.status_code == 201
    grd_id = cr.json()["id"]

    r = await client.patch(
        f"/guardians/{grd_id}/set-password",
        json={"password": "New1234!"},
        headers=auth(token),
    )
    assert r.status_code == 200

    login_r = await client.post(
        "/auth/login",
        json={"username": username, "password": "New1234!", "school_slug": slug},
    )
    assert login_r.status_code == 200


async def test_delete_guardian(client: AsyncClient, make_school):
    school, token, slug, _ = await make_school("grdd")
    cr = await client.post(
        "/guardians",
        json={
            "first_name": "Tiago",
            "last_name": "Fernandes",
            "username": f"parent-{uid()}",
            "password": "Parent1!",
        },
        headers=auth(token),
    )
    assert cr.status_code == 201
    grd_id = cr.json()["id"]

    dr = await client.delete(f"/guardians/{grd_id}", headers=auth(token))
    assert dr.status_code == 200
