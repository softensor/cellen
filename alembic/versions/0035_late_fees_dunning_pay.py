"""Late fees, dunning deliveries, principia-pay connections.

Revision ID: 0035
Revises: 0034

Phase 3 (late fees), Phase 4 (reference payments) and Phase 5 (dunning).
Every threshold lives in ``school_fee_policies`` as editable data; these
tables only record what was assessed and what was delivered.
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0035"
down_revision = "0034"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── Policy: late-fee bands and dunning schedule ──────────────────────
    op.add_column(
        "school_fee_policies",
        sa.Column("late_fee_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column(
        "school_fee_policies",
        sa.Column("late_fee_billing_item_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "school_fee_policies",
        sa.Column(
            "late_fee_base", sa.String(20), nullable=False,
            server_default=sa.text("'outstanding'"),
        ),
    )
    op.add_column(
        "school_fee_policies",
        sa.Column(
            "late_fee_bands", postgresql.JSONB(), nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )
    op.add_column(
        "school_fee_policies",
        sa.Column("dunning_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column(
        "school_fee_policies",
        sa.Column(
            "dunning_schedule", postgresql.JSONB(), nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )
    op.add_column(
        "school_fee_policies",
        sa.Column("dunning_message_template", sa.Text(), nullable=True),
    )
    op.create_foreign_key(
        "fk_fee_policy_late_fee_item",
        "school_fee_policies",
        "billing_items",
        ["late_fee_billing_item_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_check_constraint(
        "ck_fee_policy_late_fee_base",
        "school_fee_policies",
        "late_fee_base IN ('outstanding', 'document_total')",
    )

    # ── Late-fee assessments ─────────────────────────────────────────────
    op.create_table(
        "late_fee_assessments",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("source_kind", sa.String(20), nullable=False),
        sa.Column("source_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("document_number", sa.String(30), nullable=True),
        sa.Column("student_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("guardian_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("band_id", sa.String(60), nullable=False),
        sa.Column("band_percent", sa.Numeric(5, 2), nullable=False),
        sa.Column("incremental_percent", sa.Numeric(5, 2), nullable=False),
        sa.Column("base_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("fee_amount", sa.Numeric(12, 2), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("assessed_on", sa.Date(), nullable=False),
        sa.Column("instruction_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("finreg_debit_note_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("internal_invoice_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("error_code", sa.String(80), nullable=True),
        sa.Column("error_detail", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["student_id"], ["children.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["guardian_id"], ["guardians.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(
            ["instruction_id"], ["finreg_billing_instructions.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(["internal_invoice_id"], ["invoices.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "school_id", "source_kind", "source_id", "band_id",
            name="uq_late_fee_source_band",
        ),
        sa.CheckConstraint(
            "source_kind IN ('finreg_document', 'internal_invoice')",
            name="ck_late_fee_source_kind",
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'issued', 'failed', 'cancelled')", name="ck_late_fee_status"
        ),
        sa.CheckConstraint(
            "band_percent >= 0 AND band_percent <= 100", name="ck_late_fee_pct"
        ),
        sa.CheckConstraint("fee_amount >= 0", name="ck_late_fee_amount"),
    )
    op.create_index("ix_late_fee_assessments_school", "late_fee_assessments", ["school_id", "assessed_on"])
    op.create_index("ix_late_fee_assessments_source", "late_fee_assessments", ["school_id", "source_id"])

    # ── Dunning deliveries ───────────────────────────────────────────────
    op.create_table(
        "dunning_deliveries",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("source_kind", sa.String(20), nullable=False),
        sa.Column("source_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("document_number", sa.String(30), nullable=True),
        sa.Column("guardian_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("student_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("level", sa.Integer(), nullable=False),
        sa.Column("offset_days", sa.Integer(), nullable=False),
        sa.Column("channel", sa.String(20), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("message_snapshot", sa.Text(), nullable=True),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["guardian_id"], ["guardians.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["student_id"], ["children.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "school_id", "source_kind", "source_id", "offset_days", "channel",
            name="uq_dunning_source_offset_channel",
        ),
        sa.CheckConstraint(
            "source_kind IN ('finreg_document', 'internal_invoice')",
            name="ck_dunning_source_kind",
        ),
        sa.CheckConstraint(
            "status IN ('sent', 'failed', 'skipped')", name="ck_dunning_status"
        ),
    )
    op.create_index("ix_dunning_deliveries_school", "dunning_deliveries", ["school_id", "created_at"])
    op.create_index("ix_dunning_deliveries_guardian", "dunning_deliveries", ["school_id", "guardian_id"])

    # ── principia-pay per-school connection ──────────────────────────────
    op.create_table(
        "principia_pay_connections",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("client_id", sa.String(40), nullable=False),
        sa.Column("api_key_ciphertext", sa.Text(), nullable=False),
        sa.Column("callback_secret_ciphertext", sa.Text(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.ForeignKeyConstraint(["school_id"], ["schools.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("school_id", name="uq_principia_pay_connection_school"),
    )

    # ── Payment references: fiscal identity + rail bookkeeping ───────────
    # A hosted-checkout rail returns a URL instead of Multicaixa digits, so
    # the two digit columns stop being mandatory.
    op.alter_column("payment_references", "entity", existing_type=sa.String(10), nullable=True)
    op.alter_column(
        "payment_references", "reference", existing_type=sa.String(20), nullable=True
    )
    op.add_column(
        "payment_references", sa.Column("caller_reference", sa.String(255), nullable=True)
    )
    op.create_unique_constraint(
        "uq_payment_refs_provider_caller",
        "payment_references",
        ["provider", "caller_reference"],
    )
    op.add_column(
        "payment_references",
        sa.Column("finreg_document_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.add_column(
        "payment_references", sa.Column("finreg_document_number", sa.String(30), nullable=True)
    )
    op.add_column(
        "payment_references",
        sa.Column("finreg_document_external_id", sa.String(255), nullable=True),
    )
    op.add_column("payment_references", sa.Column("checkout_url", sa.String(1000), nullable=True))
    op.add_column("payment_references", sa.Column("rail_status", sa.String(30), nullable=True))
    op.add_column(
        "payment_references", sa.Column("paid_amount", sa.Numeric(12, 2), nullable=True)
    )
    op.add_column(
        "payment_references",
        sa.Column("last_checked_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_payment_references_finreg_document",
        "payment_references",
        ["school_id", "finreg_document_external_id"],
    )


def downgrade() -> None:
    # Restore the digit columns before re-imposing NOT NULL: a reference that
    # only ever had a checkout URL gets an empty placeholder, which the
    # manual flow never produces but the old schema can hold.
    op.execute(
        "UPDATE payment_references SET entity = COALESCE(entity, '') "
        "WHERE entity IS NULL"
    )
    op.execute(
        "UPDATE payment_references SET reference = COALESCE(reference, '') "
        "WHERE reference IS NULL"
    )
    op.alter_column("payment_references", "entity", existing_type=sa.String(10), nullable=False)
    op.alter_column(
        "payment_references", "reference", existing_type=sa.String(20), nullable=False
    )

    op.drop_index("ix_payment_references_finreg_document", table_name="payment_references")
    op.drop_constraint(
        "uq_payment_refs_provider_caller", "payment_references", type_="unique"
    )
    for column in (
        "caller_reference", "last_checked_at", "paid_amount", "rail_status",
        "checkout_url", "finreg_document_external_id", "finreg_document_number",
        "finreg_document_id",
    ):
        op.drop_column("payment_references", column)

    op.drop_table("principia_pay_connections")

    op.drop_index("ix_dunning_deliveries_guardian", table_name="dunning_deliveries")
    op.drop_index("ix_dunning_deliveries_school", table_name="dunning_deliveries")
    op.drop_table("dunning_deliveries")

    op.drop_index("ix_late_fee_assessments_source", table_name="late_fee_assessments")
    op.drop_index("ix_late_fee_assessments_school", table_name="late_fee_assessments")
    op.drop_table("late_fee_assessments")

    op.drop_constraint("ck_fee_policy_late_fee_base", "school_fee_policies", type_="check")
    op.drop_constraint("fk_fee_policy_late_fee_item", "school_fee_policies", type_="foreignkey")
    for column in (
        "dunning_message_template", "dunning_schedule", "dunning_enabled",
        "late_fee_bands", "late_fee_base", "late_fee_billing_item_id", "late_fee_enabled",
    ):
        op.drop_column("school_fee_policies", column)
