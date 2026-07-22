import uuid
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_db
from app.core.dependencies import get_school_id, require_school_admin
from app.core.security import hash_password
from app.models.employee import Employee
from app.models.user import User
from app.schemas.employee import EmployeeCreate, EmployeeResponse, EmployeeUpdate
from app.services.storage import save_upload

router = APIRouter(prefix="/employees", tags=["Employees"])


class SetPasswordBody(BaseModel):
    password: str


_EMPLOYEE_TYPE_TO_ROLE = {
    "teacher": "teacher",
    "staff": "staff",
    "admin": "school_admin",
}


@router.get("", response_model=list[EmployeeResponse])
async def list_employees(
    skip: int = 0,
    limit: int = 50,
    employee_type: Optional[str] = None,
    employee_status: Optional[str] = None,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    query = select(Employee).where(Employee.school_id == school_id).options(selectinload(Employee.user))
    if employee_type:
        query = query.where(Employee.employee_type == employee_type)
    if employee_status:
        query = query.where(Employee.status == employee_status)

    result = await db.execute(query.offset(skip).limit(limit))
    return result.scalars().all()


@router.post("", response_model=EmployeeResponse, status_code=201)
async def create_employee(
    body: EmployeeCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # Check username not already taken in this school
    existing = await db.execute(
        select(User).where(User.school_id == school_id, User.username == body.username)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Nome de utilizador já existe nesta escola")

    employee_data = body.model_dump(exclude={"username", "password"})
    employee = Employee(school_id=school_id, **employee_data)
    db.add(employee)
    await db.flush()  # get employee.id before creating user

    # Use explicitly provided roles, or fall back to employee_type mapping
    if body.roles:
        assigned_roles = body.roles
    else:
        assigned_roles = [_EMPLOYEE_TYPE_TO_ROLE.get(body.employee_type, "staff")]
    user = User(
        school_id=school_id,
        username=body.username,
        password_hash=hash_password(body.password),
        roles=assigned_roles,
        employee_id=employee.id,
    )
    db.add(user)
    await db.commit()
    await db.refresh(employee)
    return employee


@router.get("/{employee_id}", response_model=EmployeeResponse)
async def get_employee(
    employee_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Employee).where(Employee.id == employee_id, Employee.school_id == school_id)
        .options(selectinload(Employee.user))
    )
    employee = result.scalar_one_or_none()
    if employee is None:
        raise HTTPException(status_code=404, detail="Employee not found")
    return employee


@router.patch("/{employee_id}", response_model=EmployeeResponse)
async def update_employee(
    employee_id: uuid.UUID,
    body: EmployeeUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Employee).where(Employee.id == employee_id, Employee.school_id == school_id)
        .options(selectinload(Employee.user))
    )
    employee = result.scalar_one_or_none()
    if employee is None:
        raise HTTPException(status_code=404, detail="Employee not found")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(employee, field, value)

    await db.commit()
    await db.refresh(employee)
    return employee


@router.delete("/{employee_id}")
async def delete_employee(
    employee_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Employee).where(Employee.id == employee_id, Employee.school_id == school_id)
    )
    employee = result.scalar_one_or_none()
    if employee is None:
        raise HTTPException(status_code=404, detail="Employee not found")

    employee.status = "inactive"
    await db.commit()
    return {"message": "Employee deactivated"}


@router.patch("/{employee_id}/set-password")
async def set_employee_password(
    employee_id: uuid.UUID,
    body: "SetPasswordBody",
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(User).where(User.employee_id == employee_id, User.school_id == school_id)
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="Conta de acesso não encontrada")
    user.password_hash = hash_password(body.password)
    await db.commit()
    return {"message": "Senha actualizada"}


@router.post("/{employee_id}/photo")
async def upload_employee_photo(
    employee_id: uuid.UUID,
    file: UploadFile = File(...),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(Employee).where(Employee.id == employee_id, Employee.school_id == school_id)
    )
    employee = result.scalar_one_or_none()
    if employee is None:
        raise HTTPException(status_code=404, detail="Employee not found")

    url = await save_upload(file, "employees", employee_id)
    employee.photo_url = url
    await db.commit()
    return {"photo_url": url}
