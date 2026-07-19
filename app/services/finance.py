# -*- coding: utf-8 -*-
"""
Finance services - the core business logic layer.

Key services:
- DocumentEmissionService: single point for creating signed fiscal documents (20.20)
- PaymentIntakeService: single convergence point for all payment processing (20.11.3)
- Invoice status management
- Credit balance operations
- Reports
"""
from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from typing import List, Optional
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.finance import (
    BillingItem, BillingItemPrice, CashSession, Contract, CreditEntry, CreditNote,
    Expense, ExpenseCategory, Invoice, InvoiceLine, Payment, PaymentAllocation,
    PaymentReference, Receipt, FinanceAuditEntry,
)
from app.utils.agt import (
    compute_line, emit_document_number, format_gross_total, now_luanda, today_luanda,
)


# ─── Document Emission Service (20.20) ───────────────────────────────────────

class DocumentEmissionService:
    """
    All fiscal document creation flows through here.
    Handles: numbering, signing, chain integrity, and transmission.
    """

    def __init__(self, db: AsyncSession, school_id: UUID):
        self.db = db
        self.school_id = school_id

    async def emit_invoice(
        self,
        document_type: str,  # FT, FR, ND
        invoice_date: date,
        billing_guardian_id: Optional[UUID],
        customer_nif: Optional[str],
        customer_name: Optional[str],
        lines: List[dict],
        *,
        child_id: Optional[UUID] = None,
        due_date: Optional[date] = None,
        issued_by: Optional[UUID] = None,
        school_year_id: Optional[UUID] = None,
        reference_month: Optional[date] = None,
        description: Optional[str] = None,
        notes: Optional[str] = None,
        is_final_consumer: bool = False,
        corrected_invoice_id: Optional[UUID] = None,
        correction_reason: Optional[str] = None,
    ) -> Invoice:
        """Emit a signed FT, FR, or ND document."""
        if document_type not in ("FT", "FR", "ND"):
            raise ValueError(f"Invalid document type for invoice emission: {document_type}")

        # Compute line totals
        invoice_lines = []
        net_total = Decimal("0")
        iva_total = Decimal("0")
        gross_total = Decimal("0")

        for i, line_data in enumerate(lines, 1):
            computed = compute_line(
                unit_price=Decimal(str(line_data["unit_price"])),
                quantity=Decimal(str(line_data.get("quantity", 1))),
                discount_percent=Decimal(str(line_data.get("discount_percent", 0))),
                discount_amount=Decimal(str(line_data.get("discount_amount", 0))),
                iva_rate=Decimal(str(line_data.get("iva_rate", 0))),
            )
            net_total += computed["line_net"]
            iva_total += computed["iva_amount"]
            gross_total += computed["line_total"]

            invoice_lines.append(InvoiceLine(
                line_number=i,
                billing_item_id=line_data.get("billing_item_id"),
                description=line_data.get("description", "Serviço"),
                quantity=Decimal(str(line_data.get("quantity", 1))),
                unit_price=Decimal(str(line_data["unit_price"])),
                discount_percent=Decimal(str(line_data.get("discount_percent", 0))),
                discount_amount=Decimal(str(line_data.get("discount_amount", 0))),
                iva_rate=Decimal(str(line_data.get("iva_rate", 0))),
                iva_exemption_reason=line_data.get("iva_exemption_reason"),
                iva_exemption_legend=line_data.get("iva_exemption_legend"),
                line_net=computed["line_net"],
                iva_amount=computed["iva_amount"],
                line_total=computed["line_total"],
            ))

        # Round totals
        gross_total = gross_total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

        # Emit document number and sign (acquires series lock)
        chain = await emit_document_number(
            self.db, self.school_id, document_type, invoice_date, gross_total
        )

        invoice = Invoice(
            school_id=self.school_id,
            document_type=document_type,
            series_year=chain["series_year"],
            series_number=chain["series_number"],
            full_document_number=chain["full_document_number"],
            invoice_date=chain["invoice_date"],
            system_entry_date=chain["system_entry_date"],
            due_date=due_date,
            billing_guardian_id=billing_guardian_id,
            child_id=child_id,
            customer_nif=customer_nif,
            customer_name=customer_name,
            is_final_consumer=is_final_consumer,
            gross_total=gross_total,
            net_total=net_total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP),
            iva_total=iva_total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP),
            hash_code=chain["hash_code"],
            previous_hash=chain["previous_hash"],
            status="paid" if document_type == "FR" else "pending",
            issued_by=issued_by,
            school_year_id=school_year_id,
            reference_month=reference_month,
            description=description,
            notes=notes,
            corrected_invoice_id=corrected_invoice_id,
            correction_reason=correction_reason,
        )
        invoice.lines = invoice_lines
        self.db.add(invoice)
        await self.db.flush()

        return invoice

    async def emit_credit_note(
        self,
        invoice_id: UUID,
        reason: str,
        lines: List[dict],
        *,
        issued_by: Optional[UUID] = None,
    ) -> CreditNote:
        """
        Emit a signed NC (Nota de Crédito).
        lines: [{line_id, amount}] for partial, or all lines for full void.
        """
        # Load original invoice
        result = await self.db.execute(
            select(Invoice).where(Invoice.id == invoice_id, Invoice.school_id == self.school_id)
        )
        invoice = result.scalar_one_or_none()
        if invoice is None:
            raise ValueError("Invoice not found")
        if invoice.is_void:
            raise ValueError("Invoice is already voided")

        # Compute NC totals from the lines being credited
        net_total = Decimal("0")
        iva_total = Decimal("0")
        credited_lines = []

        if not lines:
            # Full void — credit all lines
            line_result = await self.db.execute(
                select(InvoiceLine).where(InvoiceLine.invoice_id == invoice_id)
                .order_by(InvoiceLine.line_number)
            )
            original_lines = line_result.scalars().all()
            for ol in original_lines:
                credit_amount = ol.line_total - ol.credited_amount
                if credit_amount <= 0:
                    continue
                line_net = ol.line_net - ol.credited_amount  # simplified
                line_iva = (line_net * ol.iva_rate / Decimal("100")).quantize(
                    Decimal("0.01"), rounding=ROUND_HALF_UP
                )
                net_total += line_net
                iva_total += line_iva
                ol.credited_amount = ol.line_total
                credited_lines.append({
                    "line_id": str(ol.id),
                    "description": ol.description,
                    "amount": float(credit_amount),
                })
            invoice.is_void = True
            invoice.void_reason = reason
            invoice.status = "cancelled"
        else:
            # Partial credit
            for line_spec in lines:
                line_result = await self.db.execute(
                    select(InvoiceLine).where(InvoiceLine.id == line_spec["line_id"])
                )
                ol = line_result.scalar_one_or_none()
                if ol is None:
                    raise ValueError(f"Line {line_spec['line_id']} not found")
                credit_amount = Decimal(str(line_spec["amount"]))
                available = ol.line_total - ol.credited_amount
                if credit_amount > available:
                    raise ValueError(
                        f"Cannot credit {credit_amount} on line {ol.id}; "
                        f"only {available} available"
                    )
                # Proportional net/iva split
                ratio = credit_amount / ol.line_total if ol.line_total > 0 else Decimal("0")
                line_net = (ol.line_net * ratio).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
                line_iva = (credit_amount - line_net).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
                net_total += line_net
                iva_total += line_iva
                ol.credited_amount += credit_amount
                credited_lines.append({
                    "line_id": str(ol.id),
                    "description": ol.description,
                    "amount": float(credit_amount),
                })

        gross_total = (net_total + iva_total).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

        # Sign NC
        invoice_date = today_luanda()
        chain = await emit_document_number(
            self.db, self.school_id, "NC", invoice_date, gross_total
        )

        cn = CreditNote(
            school_id=self.school_id,
            invoice_id=invoice_id,
            issued_by=issued_by,
            series_year=chain["series_year"],
            series_number=chain["series_number"],
            full_document_number=chain["full_document_number"],
            invoice_date=chain["invoice_date"],
            system_entry_date=chain["system_entry_date"],
            customer_nif=invoice.customer_nif,
            customer_name=invoice.customer_name,
            net_total=net_total,
            iva_total=iva_total,
            gross_total=gross_total,
            reason=reason,
            lines=credited_lines,
            hash_code=chain["hash_code"],
            previous_hash=chain["previous_hash"],
        )
        self.db.add(cn)
        await self.db.flush()

        # Recompute invoice balance/status if partial
        if not invoice.is_void:
            await recalculate_invoice_status(self.db, invoice_id)

        return cn

    async def emit_receipt(
        self,
        payment: Payment,
        allocations: List[dict],
        *,
        issued_by: Optional[UUID] = None,
    ) -> Receipt:
        """Emit a signed RC (Recibo) for a payment."""
        invoice_date = today_luanda()
        gross_total = payment.amount

        chain = await emit_document_number(
            self.db, self.school_id, "RC", invoice_date, gross_total
        )

        settled_docs = []
        for alloc in allocations:
            settled_docs.append({
                "invoice_id": str(alloc["invoice_id"]),
                "document_number": alloc.get("document_number"),
                "amount_applied": float(alloc["amount_applied"]),
            })

        # Determine customer info from guardian
        customer_nif = None
        customer_name = None
        if payment.billing_guardian_id:
            from app.models.person import Guardian
            g_result = await self.db.execute(
                select(Guardian).where(Guardian.id == payment.billing_guardian_id)
            )
            guardian = g_result.scalar_one_or_none()
            if guardian:
                customer_nif = guardian.nif
                customer_name = f"{guardian.first_name} {guardian.last_name}"

        receipt = Receipt(
            school_id=self.school_id,
            payment_id=payment.id,
            series_year=chain["series_year"],
            series_number=chain["series_number"],
            full_document_number=chain["full_document_number"],
            invoice_date=chain["invoice_date"],
            system_entry_date=chain["system_entry_date"],
            customer_nif=customer_nif,
            customer_name=customer_name,
            gross_total=gross_total,
            settled_documents=settled_docs,
            hash_code=chain["hash_code"],
            previous_hash=chain["previous_hash"],
            issued_by=issued_by,
        )
        self.db.add(receipt)
        await self.db.flush()
        return receipt


# ─── Payment Intake Service (20.11.3) ────────────────────────────────────────

class PaymentIntakeService:
    """
    Single convergence point for all payment processing.
    Whether from admin, parent submission, webhook, or credit application.
    """

    def __init__(self, db: AsyncSession, school_id: UUID):
        self.db = db
        self.school_id = school_id

    async def intake(
        self,
        billing_guardian_id: UUID,
        amount: Decimal,
        payment_method: str,
        payment_date: date,
        *,
        target_invoice_ids: Optional[List[UUID]] = None,
        payment_reference_id: Optional[UUID] = None,
        received_by: Optional[UUID] = None,
        cash_session_id: Optional[UUID] = None,
        idempotency_key: Optional[str] = None,
        notes: Optional[str] = None,
        receipt_proof_url: Optional[str] = None,
        skip_receipt: bool = False,
    ) -> Payment:
        """
        Process a payment:
        1. Create Payment record (with idempotency guard)
        2. Allocate to invoices (explicit targeting or oldest-first)
        3. Generate signed RC
        4. Handle surplus as CreditEntry
        5. Mark PaymentReference paid (if applicable)
        """
        # Idempotency check
        if idempotency_key:
            existing = await self.db.execute(
                select(Payment).where(
                    Payment.school_id == self.school_id,
                    Payment.idempotency_key == idempotency_key,
                )
            )
            existing_payment = existing.scalar_one_or_none()
            if existing_payment:
                return existing_payment

        # Validate cash session requirement
        if payment_method in ("cash", "check"):
            if cash_session_id:
                session_result = await self.db.execute(
                    select(CashSession).where(
                        CashSession.id == cash_session_id,
                        CashSession.school_id == self.school_id,
                        CashSession.status == "open",
                    )
                )
                if session_result.scalar_one_or_none() is None:
                    raise ValueError("Cash/check payments require an open cash session")
            # If no session provided, check if there's one open
            else:
                open_session = await self.db.execute(
                    select(CashSession).where(
                        CashSession.school_id == self.school_id,
                        CashSession.status == "open",
                    )
                )
                session = open_session.scalar_one_or_none()
                if session is None:
                    raise ValueError("No open cash session — cash/check payments require one")
                cash_session_id = session.id

        # Create payment
        payment = Payment(
            school_id=self.school_id,
            billing_guardian_id=billing_guardian_id,
            received_by=received_by,
            payment_date=payment_date,
            amount=amount,
            payment_method=payment_method,
            notes=notes,
            receipt_proof_url=receipt_proof_url,
            idempotency_key=idempotency_key,
            payment_reference_id=payment_reference_id,
            cash_session_id=cash_session_id,
        )
        self.db.add(payment)
        await self.db.flush()

        # Resolve target invoices
        if payment_reference_id:
            # Reference-originated: always target the reference's invoice
            ref_result = await self.db.execute(
                select(PaymentReference).where(PaymentReference.id == payment_reference_id)
            )
            ref = ref_result.scalar_one_or_none()
            if ref and ref.invoice_id:
                target_invoice_ids = [ref.invoice_id]

        # Allocate
        allocations = []
        remaining = amount

        if target_invoice_ids:
            for inv_id in target_invoice_ids:
                if remaining <= 0:
                    break
                inv = await self._get_invoice(inv_id)
                if inv is None:
                    continue
                balance = await get_invoice_balance(self.db, inv_id)
                applied = min(balance, remaining)
                if applied > 0:
                    alloc = PaymentAllocation(
                        payment_id=payment.id,
                        invoice_id=inv_id,
                        amount_applied=applied,
                    )
                    self.db.add(alloc)
                    allocations.append({
                        "invoice_id": inv_id,
                        "document_number": inv.full_document_number,
                        "amount_applied": applied,
                    })
                    remaining -= applied
        else:
            # Oldest-first allocation for this guardian
            pending_result = await self.db.execute(
                select(Invoice).where(
                    Invoice.school_id == self.school_id,
                    Invoice.billing_guardian_id == billing_guardian_id,
                    Invoice.status.in_(["pending", "partially_paid", "overdue"]),
                    Invoice.document_type.in_(["FT", "ND"]),
                ).order_by(Invoice.invoice_date.asc(), Invoice.series_number.asc())
            )
            pending_invoices = pending_result.scalars().all()
            for inv in pending_invoices:
                if remaining <= 0:
                    break
                balance = await get_invoice_balance(self.db, inv.id)
                applied = min(balance, remaining)
                if applied > 0:
                    alloc = PaymentAllocation(
                        payment_id=payment.id,
                        invoice_id=inv.id,
                        amount_applied=applied,
                    )
                    self.db.add(alloc)
                    allocations.append({
                        "invoice_id": inv.id,
                        "document_number": inv.full_document_number,
                        "amount_applied": applied,
                    })
                    remaining -= applied

        await self.db.flush()

        # Update invoice statuses
        for alloc in allocations:
            await recalculate_invoice_status(self.db, alloc["invoice_id"])

        # Handle surplus → CreditEntry
        if remaining > 0:
            credit = CreditEntry(
                school_id=self.school_id,
                billing_guardian_id=billing_guardian_id,
                source="payment_surplus",
                source_payment_id=payment.id,
                amount=remaining,
                amount_remaining=remaining,
                notes=f"Surplus from payment {payment.id}",
            )
            self.db.add(credit)

        # Generate RC (unless it's an FR which doesn't need a separate RC, or skip_receipt)
        if not skip_receipt and allocations:
            emission = DocumentEmissionService(self.db, self.school_id)
            await emission.emit_receipt(payment, allocations, issued_by=received_by)

        # Mark PaymentReference as paid
        if payment_reference_id:
            ref_result = await self.db.execute(
                select(PaymentReference).where(PaymentReference.id == payment_reference_id)
            )
            ref = ref_result.scalar_one_or_none()
            if ref:
                ref.status = "paid"
                ref.paid_at = now_luanda()

        await self.db.flush()
        return payment

    async def _get_invoice(self, invoice_id: UUID) -> Optional[Invoice]:
        result = await self.db.execute(
            select(Invoice).where(Invoice.id == invoice_id, Invoice.school_id == self.school_id)
        )
        return result.scalar_one_or_none()


# ─── Invoice Status Management ───────────────────────────────────────────────

async def get_invoice_balance(db: AsyncSession, invoice_id: UUID) -> Decimal:
    """Get remaining balance on an invoice (gross_total - sum of allocations - credit notes)."""
    inv_result = await db.execute(select(Invoice).where(Invoice.id == invoice_id))
    invoice = inv_result.scalar_one_or_none()
    if invoice is None:
        return Decimal("0")

    # Sum allocations from non-reversed payments
    paid_result = await db.execute(
        select(func.coalesce(func.sum(PaymentAllocation.amount_applied), Decimal("0")))
        .join(Payment, Payment.id == PaymentAllocation.payment_id)
        .where(
            PaymentAllocation.invoice_id == invoice_id,
            Payment.status == "normal",
        )
    )
    amount_paid = paid_result.scalar_one()

    # Sum credit notes
    cn_result = await db.execute(
        select(func.coalesce(func.sum(CreditNote.gross_total), Decimal("0")))
        .where(CreditNote.invoice_id == invoice_id)
    )
    amount_credited = cn_result.scalar_one()

    balance = invoice.gross_total - amount_paid - amount_credited
    return max(balance, Decimal("0"))


async def get_invoice_amount_paid(db: AsyncSession, invoice_id: UUID) -> Decimal:
    """Total amount paid on an invoice (from non-reversed payments)."""
    result = await db.execute(
        select(func.coalesce(func.sum(PaymentAllocation.amount_applied), Decimal("0")))
        .join(Payment, Payment.id == PaymentAllocation.payment_id)
        .where(
            PaymentAllocation.invoice_id == invoice_id,
            Payment.status == "normal",
        )
    )
    return result.scalar_one()


async def recalculate_invoice_status(db: AsyncSession, invoice_id: UUID) -> None:
    """Recalculate invoice status based on payments and credit notes."""
    result = await db.execute(select(Invoice).where(Invoice.id == invoice_id))
    invoice = result.scalar_one_or_none()
    if invoice is None or invoice.status == "cancelled":
        return

    balance = await get_invoice_balance(db, invoice_id)

    if balance <= 0:
        invoice.status = "paid"
    elif balance < invoice.gross_total:
        invoice.status = "partially_paid"
    else:
        if invoice.due_date and invoice.due_date < today_luanda():
            invoice.status = "overdue"
        else:
            invoice.status = "pending"

    await db.flush()


async def mark_overdue_invoices(db: AsyncSession, school_id: UUID) -> int:
    """Mark pending/partially_paid invoices as overdue if past due date."""
    today = today_luanda()
    result = await db.execute(
        select(Invoice).where(
            Invoice.school_id == school_id,
            Invoice.status.in_(["pending", "partially_paid"]),
            Invoice.due_date < today,
        )
    )
    invoices = result.scalars().all()
    count = 0
    for invoice in invoices:
        invoice.status = "overdue"
        count += 1
    if count:
        await db.flush()
    return count


# ─── Payment Reversal ────────────────────────────────────────────────────────

async def reverse_payment(
    db: AsyncSession,
    school_id: UUID,
    payment_id: UUID,
    reason: str,
    actor_id: UUID,
) -> Payment:
    """Reverse a payment: undo allocations, mark RC as Anulado, handle credits."""
    result = await db.execute(
        select(Payment).where(Payment.id == payment_id, Payment.school_id == school_id)
    )
    payment = result.scalar_one_or_none()
    if payment is None:
        raise ValueError("Payment not found")
    if payment.status == "reversed":
        raise ValueError("Payment is already reversed")

    # Check if any credit from this payment has been applied
    credit_result = await db.execute(
        select(CreditEntry).where(
            CreditEntry.source_payment_id == payment_id,
            CreditEntry.is_reversed == False,
        )
    )
    credits = credit_result.scalars().all()
    for credit in credits:
        if credit.amount_remaining < credit.amount:
            raise ValueError(
                "Cannot reverse payment — credit balance has been partially applied. "
                "Reverse the credit application first."
            )
        credit.is_reversed = True
        credit.amount_remaining = Decimal("0")

    # Get affected invoices
    alloc_result = await db.execute(
        select(PaymentAllocation).where(PaymentAllocation.payment_id == payment_id)
    )
    allocations = alloc_result.scalars().all()
    affected_invoice_ids = [a.invoice_id for a in allocations]

    # Mark payment as reversed
    payment.status = "reversed"
    payment.reverse_reason = reason
    payment.reversed_at = now_luanda()

    # Mark associated RC as Anulado
    receipt_result = await db.execute(
        select(Receipt).where(Receipt.payment_id == payment_id)
    )
    receipt = receipt_result.scalar_one_or_none()
    if receipt:
        receipt.status = "A"
        receipt.reversal_date = today_luanda()
        receipt.reversal_reason = reason

    # Return PaymentReference to active if applicable
    if payment.payment_reference_id:
        ref_result = await db.execute(
            select(PaymentReference).where(PaymentReference.id == payment.payment_reference_id)
        )
        ref = ref_result.scalar_one_or_none()
        if ref:
            if ref.expires_at and ref.expires_at < now_luanda():
                ref.status = "cancelled"
            else:
                ref.status = "active"
            ref.paid_at = None

    await db.flush()

    # Recalculate affected invoice statuses
    for inv_id in affected_invoice_ids:
        await recalculate_invoice_status(db, inv_id)

    # Audit log
    audit = FinanceAuditEntry(
        school_id=school_id,
        actor_id=actor_id,
        entity_type="payment",
        entity_id=payment_id,
        action="reverse",
        reason=reason,
    )
    db.add(audit)

    return payment


# ─── Credit Balance Operations ───────────────────────────────────────────────

async def get_guardian_credit_balance(db: AsyncSession, school_id: UUID, guardian_id: UUID) -> Decimal:
    """Sum of amount_remaining on non-reversed credit entries."""
    result = await db.execute(
        select(func.coalesce(func.sum(CreditEntry.amount_remaining), Decimal("0")))
        .where(
            CreditEntry.school_id == school_id,
            CreditEntry.billing_guardian_id == guardian_id,
            CreditEntry.is_reversed == False,
        )
    )
    return result.scalar_one()


async def apply_credit_to_invoice(
    db: AsyncSession,
    school_id: UUID,
    guardian_id: UUID,
    invoice_id: UUID,
    amount: Decimal,
    actor_id: UUID,
) -> Payment:
    """Apply guardian credit balance to an invoice (creates a 'credit' payment + RC)."""
    balance = await get_guardian_credit_balance(db, school_id, guardian_id)
    if amount > balance:
        raise ValueError(f"Insufficient credit balance: {balance} available, {amount} requested")

    # Consume credit entries FIFO
    entries_result = await db.execute(
        select(CreditEntry).where(
            CreditEntry.school_id == school_id,
            CreditEntry.billing_guardian_id == guardian_id,
            CreditEntry.is_reversed == False,
            CreditEntry.amount_remaining > 0,
        ).order_by(CreditEntry.created_at.asc())
    )
    entries = entries_result.scalars().all()
    remaining_to_consume = amount
    for entry in entries:
        if remaining_to_consume <= 0:
            break
        consume = min(entry.amount_remaining, remaining_to_consume)
        entry.amount_remaining -= consume
        remaining_to_consume -= consume

    # Create payment via intake
    intake = PaymentIntakeService(db, school_id)
    payment = await intake.intake(
        billing_guardian_id=guardian_id,
        amount=amount,
        payment_method="credit",
        payment_date=today_luanda(),
        target_invoice_ids=[invoice_id],
        notes="Credit balance application",
    )

    # Audit
    audit = FinanceAuditEntry(
        school_id=school_id,
        actor_id=actor_id,
        entity_type="credit_entry",
        entity_id=invoice_id,
        action="apply_credit",
        after_snapshot={"amount": float(amount), "invoice_id": str(invoice_id)},
    )
    db.add(audit)

    return payment


# ─── Price Resolution (20.17) ────────────────────────────────────────────────

async def resolve_unit_price(
    db: AsyncSession,
    school_id: UUID,
    billing_item_id: UUID,
    school_year_id: Optional[UUID] = None,
    contract_override: Optional[Decimal] = None,
) -> Decimal:
    """
    Resolution order: contract override → school-year price table → BillingItem default.
    """
    if contract_override is not None:
        return contract_override

    if school_year_id:
        price_result = await db.execute(
            select(BillingItemPrice.unit_price).where(
                BillingItemPrice.billing_item_id == billing_item_id,
                BillingItemPrice.school_year_id == school_year_id,
            )
        )
        year_price = price_result.scalar_one_or_none()
        if year_price is not None:
            return year_price

    item_result = await db.execute(
        select(BillingItem.unit_price).where(BillingItem.id == billing_item_id)
    )
    return item_result.scalar_one_or_none() or Decimal("0")


# ─── Reports ─────────────────────────────────────────────────────────────────

async def get_outstanding_invoices(db: AsyncSession, school_id: UUID) -> list:
    """All unpaid/overdue invoices with guardian info and days overdue."""
    from app.models.person import Child, Guardian
    today = today_luanda()

    result = await db.execute(
        select(Invoice).where(
            Invoice.school_id == school_id,
            Invoice.status.in_(["pending", "partially_paid", "overdue"]),
            Invoice.document_type.in_(["FT", "ND"]),
        ).order_by(Invoice.due_date.asc().nullslast())
    )
    invoices = result.scalars().all()

    outstanding = []
    for inv in invoices:
        amount_paid = await get_invoice_amount_paid(db, inv.id)
        balance = inv.gross_total - amount_paid
        days_overdue = max(0, (today - inv.due_date).days) if inv.due_date else 0

        # Get child/guardian names
        child_name = None
        if inv.child_id:
            child_r = await db.execute(
                select(Child.first_name, Child.last_name).where(Child.id == inv.child_id)
            )
            row = child_r.first()
            if row:
                child_name = f"{row[0]} {row[1]}"

        outstanding.append({
            "invoice_id": inv.id,
            "document_number": inv.full_document_number,
            "child_name": child_name,
            "guardian_name": inv.customer_name,
            "gross_total": inv.gross_total,
            "amount_paid": amount_paid,
            "balance": balance,
            "due_date": inv.due_date,
            "days_overdue": days_overdue,
            "status": inv.status,
        })
    return outstanding


async def generate_monthly_pl(db: AsyncSession, school_id: UUID, year: int, month: int) -> dict:
    """Monthly P&L: income from payments, expenses by category."""
    import calendar
    start_date = date(year, month, 1)
    last_day = calendar.monthrange(year, month)[1]
    end_date = date(year, month, last_day)

    income_result = await db.execute(
        select(func.coalesce(func.sum(Payment.amount), Decimal("0")))
        .where(
            Payment.school_id == school_id,
            Payment.payment_date >= start_date,
            Payment.payment_date <= end_date,
            Payment.status == "normal",
        )
    )
    income = income_result.scalar_one()

    expense_result = await db.execute(
        select(func.coalesce(func.sum(Expense.amount), Decimal("0")))
        .where(
            Expense.school_id == school_id,
            Expense.expense_date >= start_date,
            Expense.expense_date <= end_date,
            Expense.is_voided == False,
        )
    )
    total_expenses = expense_result.scalar_one()

    by_cat_result = await db.execute(
        select(
            ExpenseCategory.id,
            ExpenseCategory.name,
            func.coalesce(func.sum(Expense.amount), Decimal("0")).label("total"),
        )
        .join(Expense, Expense.category_id == ExpenseCategory.id)
        .where(
            Expense.school_id == school_id,
            Expense.expense_date >= start_date,
            Expense.expense_date <= end_date,
            Expense.is_voided == False,
        )
        .group_by(ExpenseCategory.id, ExpenseCategory.name)
    )
    by_category = [
        {"category_id": row.id, "category_name": row.name, "total": row.total}
        for row in by_cat_result.all()
    ]

    return {
        "year": year,
        "month": month,
        "income": income,
        "revenue": income,
        "expenses": total_expenses,
        "net": income - total_expenses,
        "by_category": by_category,
    }


async def generate_annual_pl(db: AsyncSession, school_id: UUID, year: int) -> dict:
    months = []
    total_income = Decimal("0")
    total_expenses = Decimal("0")
    for month in range(1, 13):
        monthly = await generate_monthly_pl(db, school_id, year, month)
        months.append(monthly)
        total_income += monthly["income"]
        total_expenses += monthly["expenses"]
    return {
        "year": year,
        "months": months,
        "total_income": total_income,
        "total_expenses": total_expenses,
        "total_net": total_income - total_expenses,
        "revenue": total_income,
        "expenses": total_expenses,
        "net": total_income - total_expenses,
    }


# ─── Guardian Account Statement (20.13) ──────────────────────────────────────

async def get_outstanding_balance(db: AsyncSession, school_id: UUID, child_id: UUID) -> Decimal:
    """Sum of outstanding balances for a child's invoices."""
    result = await db.execute(
        select(Invoice).where(
            Invoice.school_id == school_id,
            Invoice.child_id == child_id,
            Invoice.status.in_(["pending", "partially_paid", "overdue"]),
        )
    )
    invoices = result.scalars().all()
    total = Decimal("0")
    for inv in invoices:
        balance = await get_invoice_balance(db, inv.id)
        total += balance
    return total


async def get_account_statement(
    db: AsyncSession,
    school_id: UUID,
    guardian_id: UUID,
    from_date: Optional[date] = None,
    to_date: Optional[date] = None,
) -> dict:
    """Build chronological account statement for a guardian."""
    movements = []
    running_balance = Decimal("0")

    # Get all invoices (FT, FR, ND) for this guardian
    inv_query = select(Invoice).where(
        Invoice.school_id == school_id,
        Invoice.billing_guardian_id == guardian_id,
        Invoice.status != "cancelled",
    )
    if from_date:
        inv_query = inv_query.where(Invoice.invoice_date >= from_date)
    if to_date:
        inv_query = inv_query.where(Invoice.invoice_date <= to_date)
    inv_result = await db.execute(inv_query.order_by(Invoice.system_entry_date.asc()))
    invoices = inv_result.scalars().all()

    # Get credit notes
    cn_query = select(CreditNote).where(
        CreditNote.school_id == school_id,
        CreditNote.invoice_id.in_([inv.id for inv in invoices]) if invoices else CreditNote.id == None,
    )
    cn_result = await db.execute(cn_query)
    credit_notes = cn_result.scalars().all()

    # Get payments for this guardian
    pay_query = select(Payment).where(
        Payment.school_id == school_id,
        Payment.billing_guardian_id == guardian_id,
        Payment.status == "normal",
    )
    if from_date:
        pay_query = pay_query.where(Payment.payment_date >= from_date)
    if to_date:
        pay_query = pay_query.where(Payment.payment_date <= to_date)
    pay_result = await db.execute(pay_query.order_by(Payment.created_at.asc()))
    payments = pay_result.scalars().all()

    # Build combined timeline
    events = []

    for inv in invoices:
        effect = inv.gross_total
        if inv.document_type == "FR":
            # FR: +amount then -settlement (net 0)
            events.append({
                "date": inv.invoice_date,
                "timestamp": inv.system_entry_date,
                "type": "FR_issued",
                "document": inv.full_document_number,
                "description": inv.description or "Factura-Recibo",
                "debit": effect,
                "credit": effect,
            })
        elif inv.document_type == "ND":
            events.append({
                "date": inv.invoice_date,
                "timestamp": inv.system_entry_date,
                "type": "ND_issued",
                "document": inv.full_document_number,
                "description": inv.description or "Nota de Débito",
                "debit": effect,
                "credit": Decimal("0"),
            })
        else:  # FT
            events.append({
                "date": inv.invoice_date,
                "timestamp": inv.system_entry_date,
                "type": "FT_issued",
                "document": inv.full_document_number,
                "description": inv.description or "Factura",
                "debit": effect,
                "credit": Decimal("0"),
            })

    for cn in credit_notes:
        events.append({
            "date": cn.invoice_date,
            "timestamp": cn.system_entry_date,
            "type": "NC_issued",
            "document": cn.full_document_number,
            "description": f"Nota de Crédito — {cn.reason[:50]}",
            "debit": Decimal("0"),
            "credit": cn.gross_total,
        })

    for pay in payments:
        events.append({
            "date": pay.payment_date,
            "timestamp": pay.created_at,
            "type": "payment",
            "document": None,
            "description": f"Pagamento ({pay.payment_method})",
            "debit": Decimal("0"),
            "credit": pay.amount,
        })

    # Sort by timestamp
    events.sort(key=lambda e: e["timestamp"])

    # Compute running balance
    total_invoiced = Decimal("0")
    total_settled = Decimal("0")
    for event in events:
        running_balance += event["debit"] - event["credit"]
        event["running_balance"] = running_balance
        total_invoiced += event["debit"]
        total_settled += event["credit"]
        movements.append(event)

    credit_balance = await get_guardian_credit_balance(db, school_id, guardian_id)

    return {
        "guardian_id": guardian_id,
        "total_invoiced": total_invoiced,
        "total_settled": total_settled,
        "current_balance": running_balance,
        "credit_balance": credit_balance,
        "movements": movements,
    }
