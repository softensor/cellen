"""
Timetable constraint solver.

Uses OR-Tools CP-SAT when available (recommended), falls back to a greedy
algorithm otherwise. Both produce the same interface: SolverResult.

Hard constraints:
  - Teacher not double-booked (across all classes being solved simultaneously)
  - Class has at most 1 subject per (day, period) slot
  - Teacher unavailability blocks honoured
  - No double period on same day unless allow_double_period=True

Soft constraints (minimized as secondary objective):
  - Preferred time of day (morning / afternoon)
  - Subject spread across different days (not all on Monday)

Approach for partial infeasibility:
  The objective maximises total assigned periods (high weight) while minimising
  soft violations (low weight). This means if a teacher is over-committed, the
  solver assigns as many periods as possible and reports the shortfall as a
  conflict with a plain-language reason.
"""
from __future__ import annotations

import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Optional

try:
    from ortools.sat.python import cp_model as _cp_model
    _ORTOOLS = True
except ImportError:  # pragma: no cover
    _ORTOOLS = False


# ---------------------------------------------------------------------------
# Public data classes (router ↔ solver interface)
# ---------------------------------------------------------------------------

@dataclass
class SolverRequirement:
    id: uuid.UUID
    schedule_id: uuid.UUID
    subject_id: uuid.UUID
    subject_name: str
    employee_id: uuid.UUID
    employee_name: str
    periods_per_week: int
    allow_double_period: bool
    preferred_time_of_day: Optional[str]   # 'morning' | 'afternoon' | None


@dataclass
class SolverPeriod:
    id: uuid.UUID
    period_number: int


@dataclass
class SolverCell:
    schedule_id: uuid.UUID
    day_of_week: int         # 0=Mon .. 4=Fri
    period_id: uuid.UUID
    subject_id: uuid.UUID
    employee_id: uuid.UUID


@dataclass
class SolverConflict:
    requirement_id: uuid.UUID
    subject_name: str
    employee_name: str
    periods_requested: int
    periods_assigned: int
    reason: str


@dataclass
class SolverResult:
    status: str   # 'optimal' | 'feasible' | 'partial' | 'infeasible'
    cells: list[SolverCell] = field(default_factory=list)
    conflicts: list[SolverConflict] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def solve(
    requirements: list[SolverRequirement],
    periods: list[SolverPeriod],
    blocked: set[tuple],           # set of (employee_id, day_int, period_id)
    time_limit_seconds: float = 5.0,
) -> SolverResult:
    """
    Generate an optimal (or best-effort) timetable.

    Strategy:
      1. Always run greedy first — completes in milliseconds, always returns cells.
      2. If OR-Tools is available, run CP-SAT for `time_limit_seconds` to try to
         improve quality. If OR-Tools finds a better solution, return it; otherwise
         keep the greedy result. This guarantees the endpoint always responds quickly.

    Returns:
        SolverResult with cells (the proposed timetable) and conflicts (unmet
        requirements with reasons).
    """
    if not requirements:
        return SolverResult(status='optimal')

    # Step 1: fast greedy baseline — always available
    greedy = _greedy_solve(requirements, periods, blocked)

    if not _ORTOOLS:
        return greedy

    # Step 2: try to improve with OR-Tools within the time budget
    try:
        ortools = _ortools_solve(requirements, periods, blocked, time_limit_seconds)
        # Prefer OR-Tools result only if it placed at least as many cells as greedy
        if len(ortools.cells) >= len(greedy.cells):
            return ortools
    except Exception:
        pass  # OR-Tools failed for any reason — fall back to greedy

    return greedy


# ---------------------------------------------------------------------------
# OR-Tools CP-SAT solver
# ---------------------------------------------------------------------------

def _ortools_solve(
    requirements: list[SolverRequirement],
    periods: list[SolverPeriod],
    blocked: set[tuple],
    time_limit_seconds: float,
) -> SolverResult:
    cp = _cp_model

    model = cp.CpModel()
    days = list(range(5))
    n_r = len(requirements)
    n_p = len(periods)

    # x[r, d, p] = 1 if requirement r placed at day d, period p
    x = {
        (r, d, p): model.NewBoolVar(f'x_{r}_{d}_{p}')
        for r in range(n_r)
        for d in days
        for p in range(n_p)
    }

    # ── Hard: teacher unavailability ─────────────────────────────────────────
    for r, req in enumerate(requirements):
        for d in days:
            for p_i, period in enumerate(periods):
                if (req.employee_id, d, period.id) in blocked:
                    model.Add(x[r, d, p_i] == 0)

    # ── Hard: no double period unless explicitly allowed ─────────────────────
    for r, req in enumerate(requirements):
        if not req.allow_double_period:
            for d in days:
                model.Add(sum(x[r, d, p] for p in range(n_p)) <= 1)

    # ── Hard: teacher not double-booked ──────────────────────────────────────
    teacher_reqs: dict[uuid.UUID, list[int]] = defaultdict(list)
    for r, req in enumerate(requirements):
        teacher_reqs[req.employee_id].append(r)

    for emp_id, rs in teacher_reqs.items():
        for d in days:
            for p in range(n_p):
                model.Add(sum(x[r, d, p] for r in rs) <= 1)

    # ── Hard: class not double-booked ────────────────────────────────────────
    class_reqs: dict[uuid.UUID, list[int]] = defaultdict(list)
    for r, req in enumerate(requirements):
        class_reqs[req.schedule_id].append(r)

    for sched_id, rs in class_reqs.items():
        for d in days:
            for p in range(n_p):
                model.Add(sum(x[r, d, p] for r in rs) <= 1)

    # ── Objective: maximise assigned periods (primary) ────────────────────────
    # Each requirement contributes min(assigned, periods_per_week).
    # We cap via: sum(x[r,d,p]) <= periods_per_week  — solver won't exceed it.
    for r, req in enumerate(requirements):
        model.Add(
            sum(x[r, d, p] for d in days for p in range(n_p)) <= req.periods_per_week
        )

    total_assigned = sum(
        x[r, d, p]
        for r in range(n_r)
        for d in days
        for p in range(n_p)
    )

    # ── Soft: preferred time of day ───────────────────────────────────────────
    morning_cut = n_p // 2  # first half = morning periods
    soft_penalty = []

    for r, req in enumerate(requirements):
        if req.preferred_time_of_day == 'morning':
            for d in days:
                for p in range(morning_cut, n_p):   # afternoon slots
                    soft_penalty.append(x[r, d, p])
        elif req.preferred_time_of_day == 'afternoon':
            for d in days:
                for p in range(morning_cut):         # morning slots
                    soft_penalty.append(x[r, d, p])

    # ── Soft: spread subject across different days ────────────────────────────
    # Penalise assigning the same requirement twice on the same day
    # (only relevant when allow_double_period=True)
    day_overload = []
    for r, req in enumerate(requirements):
        if req.allow_double_period:
            for d in days:
                # BoolVar = 1 if ≥ 2 slots on same day for this requirement
                over = model.NewBoolVar(f'over_{r}_{d}')
                day_sum = sum(x[r, d, p] for p in range(n_p))
                # over => day_sum >= 2  (we penalise this lightly)
                model.Add(day_sum >= 2).OnlyEnforceIf(over)
                model.Add(day_sum <= 1).OnlyEnforceIf(over.Not())
                day_overload.append(over)

    penalty_expr = sum(soft_penalty) + sum(day_overload) if (soft_penalty or day_overload) else 0

    # Maximise assigned (weight 1000) and minimise soft violations (weight 1)
    model.Maximize(1000 * total_assigned - penalty_expr)

    # ── Solve ─────────────────────────────────────────────────────────────────
    solver = cp.CpSolver()
    solver.parameters.max_time_in_seconds = time_limit_seconds
    solver.parameters.num_workers = 4
    cp_status = solver.Solve(model)

    if cp_status not in (cp.OPTIMAL, cp.FEASIBLE):
        # OR-Tools couldn't find any feasible solution (timeout or truly infeasible).
        # Fall back to greedy — always produces a best-effort partial solution.
        return _greedy_solve(requirements, periods, blocked)

    cells: list[SolverCell] = []
    conflicts: list[SolverConflict] = []

    for r, req in enumerate(requirements):
        count = 0
        for d in days:
            for p_i, period in enumerate(periods):
                if solver.Value(x[r, d, p_i]) == 1:
                    cells.append(SolverCell(
                        schedule_id=req.schedule_id,
                        day_of_week=d,
                        period_id=period.id,
                        subject_id=req.subject_id,
                        employee_id=req.employee_id,
                    ))
                    count += 1

        if count < req.periods_per_week:
            conflicts.append(SolverConflict(
                requirement_id=req.id,
                subject_name=req.subject_name,
                employee_name=req.employee_name,
                periods_requested=req.periods_per_week,
                periods_assigned=count,
                reason=_diagnose(req, periods, blocked, teacher_reqs, requirements),
            ))

    is_optimal = cp_status == cp.OPTIMAL
    status = 'optimal' if is_optimal and not conflicts else (
        'feasible' if not conflicts else 'partial'
    )
    return SolverResult(status=status, cells=cells, conflicts=conflicts)


# ---------------------------------------------------------------------------
# Greedy fallback (no OR-Tools)
# ---------------------------------------------------------------------------

def _greedy_solve(
    requirements: list[SolverRequirement],
    periods: list[SolverPeriod],
    blocked: set[tuple],
) -> SolverResult:
    """
    Simple greedy solver. Processes requirements from most-constrained
    (highest periods_per_week) to least, and fills slots day-by-day trying
    to spread the subject evenly across the week.
    """
    days = list(range(5))
    teacher_used: dict[uuid.UUID, set] = defaultdict(set)
    class_used: dict[uuid.UUID, set] = defaultdict(set)

    cells: list[SolverCell] = []
    conflicts: list[SolverConflict] = []

    # Sort most-constrained first so they get first pick of slots
    sorted_reqs = sorted(requirements, key=lambda r: -r.periods_per_week)

    for req in sorted_reqs:
        assigned = 0
        day_count: dict[int, int] = defaultdict(int)

        for _ in range(req.periods_per_week):
            placed = False
            # Try days with fewest existing slots for this requirement first
            for d in sorted(days, key=lambda d: day_count[d]):
                if not req.allow_double_period and day_count[d] > 0:
                    continue
                for period in periods:
                    slot = (d, period.id)
                    if (req.employee_id, d, period.id) in blocked:
                        continue
                    if slot in teacher_used[req.employee_id]:
                        continue
                    if slot in class_used[req.schedule_id]:
                        continue
                    # Place
                    teacher_used[req.employee_id].add(slot)
                    class_used[req.schedule_id].add(slot)
                    day_count[d] += 1
                    cells.append(SolverCell(
                        schedule_id=req.schedule_id,
                        day_of_week=d,
                        period_id=period.id,
                        subject_id=req.subject_id,
                        employee_id=req.employee_id,
                    ))
                    assigned += 1
                    placed = True
                    break
                if placed:
                    break

        if assigned < req.periods_per_week:
            conflicts.append(SolverConflict(
                requirement_id=req.id,
                subject_name=req.subject_name,
                employee_name=req.employee_name,
                periods_requested=req.periods_per_week,
                periods_assigned=assigned,
                reason='Slots disponíveis insuficientes após colocação das disciplinas prioritárias',
            ))

    status = 'feasible' if not conflicts else 'partial'
    return SolverResult(status=status, cells=cells, conflicts=conflicts)


# ---------------------------------------------------------------------------
# Conflict diagnosis helper
# ---------------------------------------------------------------------------

def _diagnose(
    req: SolverRequirement,
    periods: list[SolverPeriod],
    blocked: set[tuple],
    teacher_reqs: dict[uuid.UUID, list[int]],
    all_reqs: list[SolverRequirement],
) -> str:
    days = list(range(5))
    total_slots = len(periods) * 5

    # Count available slots for this teacher
    available = sum(
        1 for d in days for period in periods
        if (req.employee_id, d, period.id) not in blocked
    )

    if available < req.periods_per_week:
        return (
            f"Professor tem disponibilidade para apenas {available} período(s) "
            f"mas são necessários {req.periods_per_week}"
        )

    # Check if teacher is over-committed across all classes
    total_needed = sum(
        all_reqs[r].periods_per_week
        for r in teacher_reqs.get(req.employee_id, [])
    )
    if total_needed > total_slots:
        return (
            f"Professor tem {total_needed} aulas pedidas no total "
            f"mas a semana tem apenas {total_slots} períodos disponíveis"
        )

    return (
        "Conflito com outros professores ou disciplinas atribuídos ao mesmo período — "
        "tente reduzir o número de aulas ou redistribuir professores"
    )
