import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_platform_admin
from app.services.storage import save_upload, delete_file

router = APIRouter(prefix="/website", tags=["Website CMS"])


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------


class SettingUpsert(BaseModel):
    key: str
    value: dict[str, Any]


class SettingResponse(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    key: str
    value: dict[str, Any]
    updated_at: Optional[datetime] = None


class PageCreate(BaseModel):
    slug: str
    title: str
    meta_description: Optional[str] = None
    is_published: bool = True
    sort_order: int = 0


class PageUpdate(BaseModel):
    slug: Optional[str] = None
    title: Optional[str] = None
    meta_description: Optional[str] = None
    is_published: Optional[bool] = None
    sort_order: Optional[int] = None


class PageResponse(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    slug: str
    title: str
    meta_description: Optional[str] = None
    is_published: bool
    sort_order: int
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class SectionCreate(BaseModel):
    page_id: uuid.UUID
    section_type: str
    name: str
    content: dict[str, Any] = {}
    settings: dict[str, Any] = {}
    sort_order: int = 0
    is_visible: bool = True


class SectionUpdate(BaseModel):
    section_type: Optional[str] = None
    name: Optional[str] = None
    content: Optional[dict[str, Any]] = None
    settings: Optional[dict[str, Any]] = None
    sort_order: Optional[int] = None
    is_visible: Optional[bool] = None


class SectionResponse(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    page_id: uuid.UUID
    section_type: str
    name: str
    content: dict[str, Any]
    settings: dict[str, Any]
    sort_order: int
    is_visible: bool
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class MediaResponse(BaseModel):
    model_config = {"from_attributes": True}
    id: uuid.UUID
    filename: str
    url: str
    alt_text: Optional[str] = None
    category: str
    file_size: Optional[int] = None
    content_type: Optional[str] = None
    created_at: Optional[datetime] = None


class PageWithSections(PageResponse):
    sections: list[SectionResponse] = []


class ContactSubmission(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    email: str = Field(min_length=3, max_length=255)
    phone: Optional[str] = Field(default=None, max_length=50)
    message: str = Field(min_length=1, max_length=10_000)
    school: Optional[str] = Field(default=None, max_length=200)


# ---------------------------------------------------------------------------
# PUBLIC endpoints — no auth, used by the website frontend
# ---------------------------------------------------------------------------


@router.get("/public/settings", response_model=list[SettingResponse])
async def public_get_settings(db: AsyncSession = Depends(get_db)):
    """Get all website settings (public, no auth required)."""
    from app.models.website import WebsiteSetting

    result = await db.execute(select(WebsiteSetting))
    return result.scalars().all()


@router.get("/public/settings/{key}", response_model=SettingResponse)
async def public_get_setting(key: str, db: AsyncSession = Depends(get_db)):
    """Get a single website setting by key (public)."""
    from app.models.website import WebsiteSetting

    result = await db.execute(
        select(WebsiteSetting).where(WebsiteSetting.key == key)
    )
    setting = result.scalar_one_or_none()
    if setting is None:
        raise HTTPException(status_code=404, detail="Setting not found")
    return setting


@router.get("/public/pages", response_model=list[PageResponse])
async def public_list_pages(db: AsyncSession = Depends(get_db)):
    """List published pages (public)."""
    from app.models.website import WebsitePage

    result = await db.execute(
        select(WebsitePage)
        .where(WebsitePage.is_published.is_(True))
        .order_by(WebsitePage.sort_order)
    )
    return result.scalars().all()


@router.get("/public/pages/{slug}", response_model=PageWithSections)
async def public_get_page(slug: str, db: AsyncSession = Depends(get_db)):
    """Get a published page with its visible sections (public)."""
    from app.models.website import WebsitePage, WebsiteSection

    result = await db.execute(
        select(WebsitePage).where(
            WebsitePage.slug == slug, WebsitePage.is_published.is_(True)
        )
    )
    page = result.scalar_one_or_none()
    if page is None:
        raise HTTPException(status_code=404, detail="Page not found")

    sections_result = await db.execute(
        select(WebsiteSection)
        .where(
            WebsiteSection.page_id == page.id,
            WebsiteSection.is_visible.is_(True),
        )
        .order_by(WebsiteSection.sort_order)
    )
    sections = sections_result.scalars().all()

    return {**page.__dict__, "sections": sections}


@router.post("/public/contact")
async def public_submit_contact(
    body: ContactSubmission,
    db: AsyncSession = Depends(get_db),
):
    """Store and email a contact-form submission from the public website."""
    from app.models.website import WebsiteContactSubmission
    from app.services.email import EmailDeliveryError, send_contact_submission_email

    submission = WebsiteContactSubmission(**body.model_dump())
    db.add(submission)
    await db.commit()

    try:
        await send_contact_submission_email(**body.model_dump())
    except EmailDeliveryError:
        submission.delivery_status = "failed"
        submission.delivery_error = "Email delivery failed"
        await db.commit()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Não foi possível enviar a mensagem. Tente novamente mais tarde.",
        )

    submission.delivery_status = "sent"
    submission.delivered_at = datetime.now(timezone.utc)
    await db.commit()
    return {"success": True, "message": "Mensagem enviada. Entraremos em contacto em breve."}


# ---------------------------------------------------------------------------
# ADMIN endpoints — platform_admin only
# ---------------------------------------------------------------------------


# --- Settings ---

@router.get("/admin/settings", response_model=list[SettingResponse])
async def admin_list_settings(
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsiteSetting

    result = await db.execute(select(WebsiteSetting))
    return result.scalars().all()


@router.put("/admin/settings", response_model=SettingResponse)
async def admin_upsert_setting(
    body: SettingUpsert,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    """Create or update a setting by key."""
    from app.models.website import WebsiteSetting

    result = await db.execute(
        select(WebsiteSetting).where(WebsiteSetting.key == body.key)
    )
    setting = result.scalar_one_or_none()
    if setting is None:
        setting = WebsiteSetting(key=body.key, value=body.value)
        db.add(setting)
    else:
        setting.value = body.value
    await db.commit()
    await db.refresh(setting)
    return setting


@router.delete("/admin/settings/{key}")
async def admin_delete_setting(
    key: str,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsiteSetting

    result = await db.execute(
        select(WebsiteSetting).where(WebsiteSetting.key == key)
    )
    setting = result.scalar_one_or_none()
    if setting is None:
        raise HTTPException(status_code=404, detail="Setting not found")
    await db.delete(setting)
    await db.commit()
    return {"message": "Setting deleted"}


# --- Pages ---

@router.get("/admin/pages", response_model=list[PageResponse])
async def admin_list_pages(
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsitePage

    result = await db.execute(
        select(WebsitePage).order_by(WebsitePage.sort_order)
    )
    return result.scalars().all()


@router.post("/admin/pages", response_model=PageResponse, status_code=status.HTTP_201_CREATED)
async def admin_create_page(
    body: PageCreate,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsitePage

    page = WebsitePage(**body.model_dump())
    db.add(page)
    await db.commit()
    await db.refresh(page)
    return page


@router.get("/admin/pages/{page_id}", response_model=PageWithSections)
async def admin_get_page(
    page_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsitePage, WebsiteSection

    result = await db.execute(
        select(WebsitePage).where(WebsitePage.id == page_id)
    )
    page = result.scalar_one_or_none()
    if page is None:
        raise HTTPException(status_code=404, detail="Page not found")

    sections_result = await db.execute(
        select(WebsiteSection)
        .where(WebsiteSection.page_id == page.id)
        .order_by(WebsiteSection.sort_order)
    )
    sections = sections_result.scalars().all()
    return {**page.__dict__, "sections": sections}


@router.patch("/admin/pages/{page_id}", response_model=PageResponse)
async def admin_update_page(
    page_id: uuid.UUID,
    body: PageUpdate,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsitePage

    result = await db.execute(
        select(WebsitePage).where(WebsitePage.id == page_id)
    )
    page = result.scalar_one_or_none()
    if page is None:
        raise HTTPException(status_code=404, detail="Page not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(page, field, value)
    await db.commit()
    await db.refresh(page)
    return page


@router.delete("/admin/pages/{page_id}")
async def admin_delete_page(
    page_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsitePage, WebsiteSection

    result = await db.execute(
        select(WebsitePage).where(WebsitePage.id == page_id)
    )
    page = result.scalar_one_or_none()
    if page is None:
        raise HTTPException(status_code=404, detail="Page not found")
    # Delete all sections in this page
    sections = await db.execute(
        select(WebsiteSection).where(WebsiteSection.page_id == page_id)
    )
    for section in sections.scalars().all():
        await db.delete(section)
    await db.delete(page)
    await db.commit()
    return {"message": "Page and its sections deleted"}


# --- Sections ---

@router.get("/admin/sections", response_model=list[SectionResponse])
async def admin_list_sections(
    page_id: Optional[uuid.UUID] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsiteSection

    query = select(WebsiteSection)
    if page_id:
        query = query.where(WebsiteSection.page_id == page_id)
    result = await db.execute(query.order_by(WebsiteSection.sort_order))
    return result.scalars().all()


@router.get("/admin/sections/{section_id}", response_model=SectionResponse)
async def admin_get_section(
    section_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsiteSection

    result = await db.execute(
        select(WebsiteSection).where(WebsiteSection.id == section_id)
    )
    section = result.scalar_one_or_none()
    if section is None:
        raise HTTPException(status_code=404, detail="Section not found")
    return section


@router.post("/admin/sections", response_model=SectionResponse, status_code=status.HTTP_201_CREATED)
async def admin_create_section(
    body: SectionCreate,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsiteSection

    section = WebsiteSection(**body.model_dump())
    db.add(section)
    await db.commit()
    await db.refresh(section)
    return section


@router.patch("/admin/sections/{section_id}", response_model=SectionResponse)
async def admin_update_section(
    section_id: uuid.UUID,
    body: SectionUpdate,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsiteSection

    result = await db.execute(
        select(WebsiteSection).where(WebsiteSection.id == section_id)
    )
    section = result.scalar_one_or_none()
    if section is None:
        raise HTTPException(status_code=404, detail="Section not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(section, field, value)
    await db.commit()
    await db.refresh(section)
    return section


@router.delete("/admin/sections/{section_id}")
async def admin_delete_section(
    section_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsiteSection

    result = await db.execute(
        select(WebsiteSection).where(WebsiteSection.id == section_id)
    )
    section = result.scalar_one_or_none()
    if section is None:
        raise HTTPException(status_code=404, detail="Section not found")
    await db.delete(section)
    await db.commit()
    return {"message": "Section deleted"}


@router.put("/admin/sections/reorder")
async def admin_reorder_sections(
    orders: list[dict[str, Any]],
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    """Reorder sections. Body: [{"id": "uuid", "sort_order": 0}, ...]"""
    from app.models.website import WebsiteSection

    for item in orders:
        result = await db.execute(
            select(WebsiteSection).where(
                WebsiteSection.id == uuid.UUID(str(item["id"]))
            )
        )
        section = result.scalar_one_or_none()
        if section:
            section.sort_order = item["sort_order"]
    await db.commit()
    return {"message": "Sections reordered"}


# --- Media ---

@router.get("/admin/media", response_model=list[MediaResponse])
async def admin_list_media(
    category: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsiteMedia

    query = select(WebsiteMedia)
    if category:
        query = query.where(WebsiteMedia.category == category)
    result = await db.execute(query.order_by(WebsiteMedia.created_at.desc()))
    return result.scalars().all()


@router.post("/admin/media", response_model=MediaResponse, status_code=status.HTTP_201_CREATED)
async def admin_upload_media(
    file: UploadFile = File(...),
    alt_text: str = "",
    category: str = "general",
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsiteMedia

    media_id = uuid.uuid4()
    url = await save_upload(file, "website", media_id)
    content = await file.read()

    media = WebsiteMedia(
        id=media_id,
        filename=file.filename or "upload",
        url=url,
        alt_text=alt_text or None,
        category=category,
        file_size=len(content) if content else None,
        content_type=file.content_type,
    )
    db.add(media)
    await db.commit()
    await db.refresh(media)
    return media


@router.delete("/admin/media/{media_id}")
async def admin_delete_media(
    media_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    from app.models.website import WebsiteMedia

    result = await db.execute(
        select(WebsiteMedia).where(WebsiteMedia.id == media_id)
    )
    media = result.scalar_one_or_none()
    if media is None:
        raise HTTPException(status_code=404, detail="Media not found")
    await delete_file(media.url)
    await db.delete(media)
    await db.commit()
    return {"message": "Media deleted"}


# --- Seed / Initialize ---

@router.post("/admin/seed", status_code=status.HTTP_201_CREATED)
async def admin_seed_website(
    db: AsyncSession = Depends(get_db),
    _=Depends(require_platform_admin),
):
    """Seed the website with default content. Safe to call multiple times — skips if home page exists."""
    from app.models.website import WebsiteSetting, WebsitePage, WebsiteSection

    # Check if already seeded
    existing = await db.execute(
        select(WebsitePage).where(WebsitePage.slug == "home")
    )
    if existing.scalar_one_or_none():
        return {"message": "Website already seeded"}

    # Global settings
    settings_data = [
        ("site_name", {"value": "Cellen"}),
        ("site_tagline", {"value": "Gest\u00e3o Escolar Inteligente"}),
        ("contact_email", {"value": "info@cellen.ao"}),
        ("contact_phone", {"value": "+244 923 000 000"}),
        ("contact_address", {"value": "Luanda, Angola"}),
        ("working_hours", {"value": "Segunda a Sexta, 8h \u2014 17h"}),
        ("social_links", {
            "facebook": "",
            "instagram": "",
            "linkedin": "",
            "whatsapp": "+244923000000",
        }),
        ("brand_colors", {
            "primary": "#2563EB",
            "primary_dark": "#1D4ED8",
            "accent": "#F59E0B",
            "dark": "#0F172A",
        }),
        ("footer_text", {"value": "\u00a9 2026 Cellen. Todos os direitos reservados."}),
        ("seo", {
            "title": "Cellen \u2014 Gest\u00e3o Escolar Inteligente",
            "description": "Plataforma de gest\u00e3o para creches, jardins de inf\u00e2ncia e ber\u00e7\u00e1rios em Angola.",
        }),
    ]
    for key, value in settings_data:
        db.add(WebsiteSetting(key=key, value=value))

    # Home page
    home = WebsitePage(slug="home", title="P\u00e1gina Inicial", sort_order=0)
    db.add(home)
    await db.flush()

    # Home sections
    sections = [
        WebsiteSection(
            page_id=home.id,
            section_type="hero",
            name="Hero Principal",
            sort_order=0,
            content={
                "badge": "\ud83c\udde6\ud83c\uddf4 Feito para escolas em Angola",
                "title": "Gest\u00e3o escolar <em>simples e completa</em> para a sua institui\u00e7\u00e3o",
                "subtitle": "Matr\u00edculas, pagamentos, comunica\u00e7\u00e3o com pais, relat\u00f3rios e muito mais \u2014 tudo numa s\u00f3 plataforma.",
                "cta_primary": {"text": "Solicitar Demonstra\u00e7\u00e3o", "link": "#contacto"},
                "cta_secondary": {"text": "Ver Funcionalidades", "link": "#funcionalidades"},
                "stats": [
                    {"number": "12+", "label": "M\u00f3dulos integrados"},
                    {"number": "5", "label": "Perfis de utilizador"},
                    {"number": "100%", "label": "Adaptado a Angola"},
                ],
            },
            settings={"background": "gradient"},
        ),
        WebsiteSection(
            page_id=home.id,
            section_type="features",
            name="Funcionalidades",
            sort_order=1,
            content={
                "title": "Tudo o que a sua escola precisa",
                "subtitle": "Uma plataforma completa para gerir todos os aspectos do dia-a-dia escolar.",
                "items": [
                    {"icon": "\ud83d\udcda", "color": "blue", "title": "Matr\u00edculas e Inscri\u00e7\u00f5es", "description": "Processo de matr\u00edcula digital com gest\u00e3o de documentos, turmas e dados dos alunos num s\u00f3 lugar."},
                    {"icon": "\ud83d\udcb0", "color": "amber", "title": "Gest\u00e3o Financeira", "description": "Controlo de mensalidades, gera\u00e7\u00e3o de facturas, registo de pagamentos e relat\u00f3rios financeiros completos."},
                    {"icon": "\ud83d\udcac", "color": "green", "title": "Comunica\u00e7\u00e3o com Pais", "description": "Mensagens directas, an\u00fancios, caderneta digital e notifica\u00e7\u00f5es autom\u00e1ticas para encarregados de educa\u00e7\u00e3o."},
                    {"icon": "\ud83d\udccb", "color": "purple", "title": "Assiduidade e Presen\u00e7as", "description": "Registo di\u00e1rio de presen\u00e7as com notifica\u00e7\u00e3o autom\u00e1tica aos pais em caso de falta."},
                    {"icon": "\ud83c\udfe5", "color": "pink", "title": "Sa\u00fade e Seguran\u00e7a", "description": "Registo de alergias, vacinas, incidentes e autoriza\u00e7\u00f5es de sa\u00edda \u2014 tudo documentado e acess\u00edvel."},
                    {"icon": "\ud83d\udcca", "color": "teal", "title": "Relat\u00f3rios e Painel", "description": "Dashboard em tempo real com KPIs, estat\u00edsticas de cobran\u00e7a, assiduidade e evolu\u00e7\u00e3o dos alunos."},
                ],
            },
            settings={"background": "gray", "columns": 3},
        ),
        WebsiteSection(
            page_id=home.id,
            section_type="steps",
            name="Como Funciona",
            sort_order=2,
            content={
                "title": "Como funciona",
                "subtitle": "Comece a usar o Cellen em poucos passos.",
                "items": [
                    {"title": "Registe a sua escola", "description": "Preencha os dados da institui\u00e7\u00e3o e receba acesso imediato \u00e0 plataforma."},
                    {"title": "Configure turmas e alunos", "description": "Importe ou crie turmas, inscreva alunos e convide educadores e pais."},
                    {"title": "Comece a gerir", "description": "Utilize todos os m\u00f3dulos: presen\u00e7as, pagamentos, comunica\u00e7\u00e3o e muito mais."},
                    {"title": "Acompanhe resultados", "description": "Analise relat\u00f3rios e tome decis\u00f5es informadas para melhorar a sua escola."},
                ],
            },
            settings={},
        ),
        WebsiteSection(
            page_id=home.id,
            section_type="benefits",
            name="Benef\u00edcios",
            sort_order=3,
            content={
                "title": "Porqu\u00ea escolher o Cellen?",
                "subtitle": "Desenhado para a realidade das escolas angolanas.",
                "items": [
                    {"title": "Multi-moeda (AOA, USD, EUR)", "description": "Factura\u00e7\u00e3o na moeda que a sua escola utiliza, sem complica\u00e7\u00f5es."},
                    {"title": "Aplica\u00e7\u00e3o m\u00f3vel para pais", "description": "Os encarregados acompanham tudo pelo telem\u00f3vel \u2014 presen\u00e7as, mensagens, pagamentos."},
                    {"title": "Dados seguros e isolados", "description": "Cada escola tem os seus dados completamente separados. Privacidade garantida."},
                    {"title": "Sem instala\u00e7\u00e3o de software", "description": "Funciona no navegador e no telem\u00f3vel. Sem necessidade de servidores locais."},
                    {"title": "Suporte em portugu\u00eas", "description": "Equipa de suporte que fala a sua l\u00edngua e entende o seu contexto."},
                ],
                "metrics": [
                    {"number": "80%", "label": "Menos tempo administrativo"},
                    {"number": "95%", "label": "Taxa de cobran\u00e7a"},
                    {"number": "3x", "label": "Mais envolvimento dos pais"},
                    {"number": "0", "label": "Pap\u00e9is perdidos"},
                ],
                "metrics_title": "Resultados que importam",
                "metrics_subtitle": "Escolas que digitalizam a gest\u00e3o ganham efici\u00eancia imediata.",
            },
            settings={"background": "gray"},
        ),
        WebsiteSection(
            page_id=home.id,
            section_type="pricing",
            name="Pre\u00e7os",
            sort_order=4,
            content={
                "title": "Planos simples e transparentes",
                "subtitle": "Escolha o plano ideal para o tamanho da sua escola.",
                "plans": [
                    {
                        "name": "Essencial",
                        "description": "Para escolas pequenas",
                        "price": "25.000",
                        "currency": "AOA",
                        "period": "m\u00eas",
                        "note": "At\u00e9 50 alunos",
                        "popular": False,
                        "cta": {"text": "Come\u00e7ar", "link": "#contacto"},
                        "features": [
                            "Matr\u00edculas e turmas",
                            "Registo de presen\u00e7as",
                            "Mensagens aos pais",
                            "Gest\u00e3o financeira b\u00e1sica",
                            "Suporte por email",
                        ],
                    },
                    {
                        "name": "Profissional",
                        "description": "Para escolas em crescimento",
                        "price": "50.000",
                        "currency": "AOA",
                        "period": "m\u00eas",
                        "note": "At\u00e9 200 alunos",
                        "popular": True,
                        "cta": {"text": "Escolher", "link": "#contacto"},
                        "features": [
                            "Tudo do plano Essencial",
                            "Relat\u00f3rios avan\u00e7ados",
                            "Caderneta digital completa",
                            "Gest\u00e3o de sa\u00fade",
                            "App m\u00f3vel para pais",
                            "Suporte priorit\u00e1rio",
                        ],
                    },
                    {
                        "name": "Institucional",
                        "description": "Para grandes institui\u00e7\u00f5es",
                        "price": "Sob consulta",
                        "currency": "",
                        "period": "",
                        "note": "Alunos ilimitados",
                        "popular": False,
                        "cta": {"text": "Falar connosco", "link": "#contacto"},
                        "features": [
                            "Tudo do plano Profissional",
                            "M\u00faltiplos campus",
                            "Website da escola inclu\u00eddo",
                            "Integra\u00e7\u00f5es personalizadas",
                            "Gestor de conta dedicado",
                            "Forma\u00e7\u00e3o presencial",
                        ],
                    },
                ],
            },
            settings={},
        ),
        WebsiteSection(
            page_id=home.id,
            section_type="contact",
            name="Contacto",
            sort_order=5,
            content={
                "title": "Fale connosco",
                "subtitle": "Tem d\u00favidas ou quer uma demonstra\u00e7\u00e3o? Estamos \u00e0 disposi\u00e7\u00e3o.",
                "form_fields": [
                    {"name": "name", "label": "O seu nome", "type": "text", "required": True, "half": True},
                    {"name": "school", "label": "Nome da escola", "type": "text", "required": False, "half": True},
                    {"name": "email", "label": "Email", "type": "email", "required": True, "half": False},
                    {"name": "phone", "label": "Telefone / WhatsApp", "type": "tel", "required": False, "half": False},
                    {"name": "message", "label": "A sua mensagem...", "type": "textarea", "required": True, "half": False},
                ],
                "submit_text": "Enviar Mensagem",
            },
            settings={"background": "dark"},
        ),
    ]
    for s in sections:
        db.add(s)

    await db.commit()
    return {"message": "Website seeded with default content"}
