"""Finreg integration mappings and transactional billing outbox.

Revision ID: 0025
Revises: 0024
"""
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0025"
down_revision = "0024"
branch_labels = None
depends_on = None


def _timestamps():
    return [
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    ]


def upgrade():
    op.create_table(
        "finreg_school_connections",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id"), nullable=False),
        sa.Column("finreg_company_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("mode", sa.String(20), nullable=False, server_default="disabled"),
        sa.Column("kill_switch", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("last_event_sequence", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_sync_at", sa.DateTime(timezone=True)), *_timestamps(),
        sa.UniqueConstraint("school_id", name="uq_finreg_connection_school"),
        sa.CheckConstraint("mode IN ('disabled','fake','shadow','pilot','live')", name="ck_finreg_connection_mode"),
    )
    op.create_table(
        "finreg_entity_mappings",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id"), nullable=False),
        sa.Column("entity_type", sa.String(30), nullable=False),
        sa.Column("cellen_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("finreg_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("external_version", sa.String(80)),
        sa.Column("status", sa.String(20), nullable=False, server_default="confirmed"),
        sa.Column("last_error_code", sa.String(80)), *_timestamps(),
        sa.UniqueConstraint("school_id", "entity_type", "cellen_id", name="uq_finreg_mapping_cellen"),
        sa.UniqueConstraint("school_id", "entity_type", "finreg_id", name="uq_finreg_mapping_finreg"),
    )
    op.create_table(
        "finreg_billing_instructions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id"), nullable=False),
        sa.Column("contract_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("contracts.id")),
        sa.Column("idempotency_key", sa.String(255), nullable=False),
        sa.Column("correlation_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("command_type", sa.String(50), nullable=False, server_default="issue_invoice"),
        sa.Column("payload", postgresql.JSONB(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="pending"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True)),
        sa.Column("finreg_document_id", postgresql.UUID(as_uuid=True)),
        sa.Column("result_snapshot", postgresql.JSONB()),
        sa.Column("error_code", sa.String(80)), sa.Column("error_detail", sa.Text()), *_timestamps(),
        sa.UniqueConstraint("school_id", "idempotency_key", name="uq_finreg_instruction_key"),
        sa.CheckConstraint("status IN ('pending','processing','confirmed','failed','rejected','unknown')", name="ck_finreg_instruction_status"),
    )
    op.create_index("ix_finreg_instruction_dispatch", "finreg_billing_instructions", ["status", "next_attempt_at"])
    op.create_table(
        "finreg_event_receipts",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("school_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("schools.id"), nullable=False),
        sa.Column("event_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("sequence_id", sa.Integer(), nullable=False),
        sa.Column("event_type", sa.String(80), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("school_id", "event_id", name="uq_finreg_event_receipt"),
    )


def downgrade():
    op.drop_table("finreg_event_receipts")
    op.drop_table("finreg_billing_instructions")
    op.drop_table("finreg_entity_mappings")
    op.drop_table("finreg_school_connections")
