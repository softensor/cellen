import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_school_id, require_school_admin, require_teacher
from app.core.security import hash_password
from app.models.academic import Enrollment, SchoolYear
from app.models.employee import Employee
from app.models.finance import Invoice, Payment, PaymentAllocation
from app.models.person import Child
from app.models.school import School
from app.models.user import User
from app.schemas.academic import (
    SchoolYearCreate, SchoolYearResponse, SchoolYearUpdate
)
from app.schemas.school import SchoolResponse, SchoolUpdate
from app.schemas.user import UserCreate, UserResponse, UserUpdate

router = APIRouter(prefix="/schools", tags=["Schools"])


@router.get("/info", response_model=SchoolResponse)
async def get_school_info(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    """Basic school info (name, logo, currency) accessible to all authenticated users."""
    result = await db.execute(select(School).where(School.id == school_id))
    school = result.scalar_one_or_none()
    if school is None:
        raise HTTPException(status_code=404, detail="School not found")
    return school


@router.get("/me", response_model=SchoolResponse)
async def get_my_school(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(select(School).where(School.id == school_id))
    school = result.scalar_one_or_none()
    if school is None:
        raise HTTPException(status_code=404, detail="School not found")
    return school


@router.post("/logo", response_model=SchoolResponse)
async def upload_school_logo(
    file: UploadFile = File(...),
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from app.services.storage import delete_file, save_upload

    result = await db.execute(select(School).where(School.id == school_id))
    school = result.scalar_one_or_none()
    if school is None:
        raise HTTPException(status_code=404, detail="School not found")

    if file.content_type not in ("image/jpeg", "image/png", "image/webp"):
        raise HTTPException(status_code=400, detail="Apenas imagens JPEG, PNG ou WebP são permitidas")

    # Remove old logo from storage if it was a local upload
    if school.logo_url and school.logo_url.startswith("/media/"):
        await delete_file(school.logo_url)

    url = await save_upload(file, "schools", school_id)
    school.logo_url = url
    await db.commit()
    await db.refresh(school)
    return school


@router.patch("/me", response_model=SchoolResponse)
async def update_my_school(
    body: SchoolUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(select(School).where(School.id == school_id))
    school = result.scalar_one_or_none()
    if school is None:
        raise HTTPException(status_code=404, detail="School not found")

    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(school, field, value)

    await db.commit()
    await db.refresh(school)
    return school


@router.post("/me/whatsapp/test")
async def test_whatsapp(
    body: dict,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    """Send a test WhatsApp message to verify configuration."""
    from app.services.whatsapp import send_whatsapp

    result = await db.execute(select(School).where(School.id == school_id))
    school = result.scalar_one_or_none()
    if school is None:
        raise HTTPException(status_code=404, detail="School not found")

    phone = body.get("phone")
    if not phone:
        raise HTTPException(status_code=422, detail="phone is required")

    success = await send_whatsapp(
        phone,
        f"✅ Cellen — Teste de ligação WhatsApp para {school.name}. Configuração correcta!",
        phone_number_id=school.wa_phone_number_id or None,
        access_token=school.wa_access_token or None,
    )
    if not success:
        raise HTTPException(
            status_code=502,
            detail="Mensagem não enviada. Verifique as credenciais e o número de telefone.",
        )
    return {"sent": True}


@router.get("/me/stats")
async def get_school_stats(
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    from datetime import date
    import calendar

    children_count_result = await db.execute(
        select(func.count(Child.id)).where(Child.school_id == school_id, Child.is_active)
    )
    children_count = children_count_result.scalar_one()

    teachers_count_result = await db.execute(
        select(func.count(Employee.id)).where(
            Employee.school_id == school_id,
            Employee.employee_type == "teacher",
            Employee.status == "active",
        )
    )
    teachers_count = teachers_count_result.scalar_one()

    enrollments_count_result = await db.execute(
        select(func.count(Enrollment.id)).where(
            Enrollment.school_id == school_id, Enrollment.status == "active"
        )
    )
    active_enrollments = enrollments_count_result.scalar_one()

    # Monthly revenue (payments received this month)
    today = date.today()
    start_of_month = date(today.year, today.month, 1)
    last_day = calendar.monthrange(today.year, today.month)[1]
    end_of_month = date(today.year, today.month, last_day)

    revenue_result = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), Decimal("0")))
        .where(
            Payment.school_id == school_id,
            Payment.payment_date >= start_of_month,
            Payment.payment_date <= end_of_month,
        )
    )
    monthly_revenue = revenue_result.scalar_one()

    from app.models.finance import Expense

    expenses_result = await db.execute(
        select(func.coalesce(func.sum(Expense.amount), Decimal("0")))
        .where(
            Expense.school_id == school_id,
            Expense.expense_date >= start_of_month,
            Expense.expense_date <= end_of_month,
        )
    )
    monthly_expenses = expenses_result.scalar_one()

    # Outstanding balance total
    invoices_result = await db.execute(
        select(Invoice).where(
            Invoice.school_id == school_id,
            Invoice.status.in_(["pending", "partially_paid", "overdue"]),
        )
    )
    invoices = invoices_result.scalars().all()

    outstanding_total = Decimal("0")
    for invoice in invoices:
        paid_result = await db.execute(
            select(func.coalesce(func.sum(PaymentAllocation.amount_applied), Decimal("0")))
            .where(PaymentAllocation.invoice_id == invoice.id)
        )
        amount_paid = paid_result.scalar_one()
        outstanding_total += invoice.gross_total - amount_paid

    return {
        "children_count": children_count,
        "teachers_count": teachers_count,
        "active_enrollments": active_enrollments,
        "monthly_revenue": monthly_revenue,
        "monthly_expenses": monthly_expenses,
        "outstanding_balance_total": outstanding_total,
    }


# Users management
@router.get("/users", response_model=list[UserResponse])
async def list_users(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(User).where(User.school_id == school_id).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.post("/users", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    body: UserCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # Check username uniqueness within school
    existing = await db.execute(
        select(User).where(User.school_id == school_id, User.username == body.username)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Username already in use in this school")

    # Validate: employee_id XOR guardian_id
    if body.employee_id and body.guardian_id:
        raise HTTPException(status_code=400, detail="User can only link to employee OR guardian, not both")

    user = User(
        school_id=school_id,
        username=body.username,
        password_hash=hash_password(body.password),
        roles=[body.role],
        is_active=body.is_active,
        employee_id=body.employee_id,
        guardian_id=body.guardian_id,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@router.patch("/users/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: uuid.UUID,
    body: UserUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(User).where(User.id == user_id, User.school_id == school_id)
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    update_data = body.model_dump(exclude_unset=True)
    if "password" in update_data:
        update_data["password_hash"] = hash_password(update_data.pop("password"))
    if "role" in update_data:
        update_data["roles"] = [update_data.pop("role")]

    # Validate XOR constraint if both are being set
    new_employee_id = update_data.get("employee_id", user.employee_id)
    new_guardian_id = update_data.get("guardian_id", user.guardian_id)
    if new_employee_id and new_guardian_id:
        raise HTTPException(status_code=400, detail="User can only link to employee OR guardian, not both")

    for field, value in update_data.items():
        setattr(user, field, value)

    await db.commit()
    await db.refresh(user)
    return user


@router.delete("/users/{user_id}")
async def deactivate_user(
    user_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(User).where(User.id == user_id, User.school_id == school_id)
    )
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    user.is_active = False
    await db.commit()
    return {"message": "User deactivated"}


# School years
@router.get("/school-years", response_model=list[SchoolYearResponse])
async def list_school_years(
    skip: int = 0,
    limit: int = 50,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(get_current_user),
):
    result = await db.execute(
        select(SchoolYear).where(SchoolYear.school_id == school_id).offset(skip).limit(limit)
    )
    return result.scalars().all()


@router.post("/school-years", response_model=SchoolYearResponse, status_code=status.HTTP_201_CREATED)
async def create_school_year(
    body: SchoolYearCreate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    sy = SchoolYear(
        school_id=school_id,
        year_label=body.year_label,
        start_date=body.start_date,
        end_date=body.end_date,
        is_active=body.is_active,
    )
    db.add(sy)
    await db.commit()
    await db.refresh(sy)
    return sy


@router.patch("/school-years/{year_id}", response_model=SchoolYearResponse)
async def update_school_year(
    year_id: uuid.UUID,
    body: SchoolYearUpdate,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    result = await db.execute(
        select(SchoolYear).where(SchoolYear.id == year_id, SchoolYear.school_id == school_id)
    )
    sy = result.scalar_one_or_none()
    if sy is None:
        raise HTTPException(status_code=404, detail="School year not found")

    update_data = body.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(sy, field, value)

    await db.commit()
    await db.refresh(sy)
    return sy


@router.post("/school-years/{year_id}/activate", response_model=SchoolYearResponse)
async def activate_school_year(
    year_id: uuid.UUID,
    school_id: uuid.UUID = Depends(get_school_id),
    db: AsyncSession = Depends(get_db),
    _=Depends(require_school_admin),
):
    # Deactivate all school years for this school
    all_years_result = await db.execute(
        select(SchoolYear).where(SchoolYear.school_id == school_id)
    )
    for sy in all_years_result.scalars().all():
        sy.is_active = False

    # Activate the target
    result = await db.execute(
        select(SchoolYear).where(SchoolYear.id == year_id, SchoolYear.school_id == school_id)
    )
    sy = result.scalar_one_or_none()
    if sy is None:
        raise HTTPException(status_code=404, detail="School year not found")

    sy.is_active = True
    await db.commit()
    await db.refresh(sy)
    return sy
