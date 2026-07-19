# Cellen — Product Specification
    
**Version 1.2 | Childcare Management SaaS (Angola)**

---

## 1. Overview

Cellen is a multi-tenant SaaS platform for managing childcare centres (creches, jardins de infância, berçários). Each tenant is a **School**. The platform is operated by a **Platform Admin** who provisions schools and their administrators.

Note: the implementation of this spec shall result in a modern application, that is comprises:
- Interactivity (really important, information provided in an easy way, connections between features, easy to find information with simple clicks)

- Easiness
- Compelleness
- Excellent user experience

### 1.1 Tenant Isolation

Every record belongs to exactly one school (`school_id`). No query may return data from another school. This is enforced at the API layer — all routes resolve `school_id` from the authenticated user's token, never from a client-supplied parameter.

### 1.2 Roles

| Role             | Description                                                                                                                      |
|------------------|----------------------------------------------------------------------------------------------------------------------------------|
| `platform_admin` | Manages schools, billing, platform health. Sees all data.                                                                        |
| `school_admin`   | Full access within their school.                                                                                                 |
| `teacher`        | Manages attendance, caderneta, health events, incidents. Read-only access to children and schedules in their classes.            |
| `staff`          | Non-teaching school employee. Limited access — sees own appointments, announcements, events.                                     |
| `parent`         | Guardian linked to one or more children. Read-only on school data; read/write on their own children's parent-specific endpoints. |

---

## 2. Platform Administration

### 2.1 School Lifecycle

**Use cases:**
- UC-P1: Create a new school account
- UC-P2: View all schools with key stats
- UC-P3: Activate or deactivate a school
- UC-P4: Edit school metadata (name, NIF, slug)

**Workflow — Onboarding a new school:**
1. Platform admin creates school: `POST /platform/schools` with `name`, `slug`, `nif`, `currency`.
2. System creates a default `school_admin` user account and returns credentials.
3. Platform admin activates the school: `POST /platform/schools/{id}/activate`.
4. School admin receives credentials and logs in.
5. School admin configures their school profile (logo, legal name, city) before using the system.

**Business rules:**
- `slug` must be globally unique, URL-safe, lowercase (regex `[a-z0-9\-]+`). Used as the subdomain/tenant identifier during login.
- `nif` (Número de Identificação Fiscal) must be exactly 9 digits (Angola standard).
- `currency` defaults to `AOA`. Supported values: `AOA`, `USD`, `EUR`.
- An inactive school's users cannot log in.
- Platform admin cannot log in to a school's scope — they operate only at platform level.

**Platform dashboard KPIs:**
- Total schools (active / inactive)
- Total children enrolled across all schools
- Total active users across all schools
- Monthly new school registrations

---

## 3. Authentication

### 3.1 Login

**Use cases:**
- UC-A1: Employee/admin logs in with username + password + school slug
- UC-A2: Parent logs in with username + password + school slug
- UC-A3: Token refresh (silent re-authentication)
- UC-A4: Logout (client-side token discard)
- UC-A5: Change own password

**Workflow — Login:**
1. User provides `username`, `password`, `school_slug`.
2. System resolves school from slug; rejects if school is inactive.
3. System validates credentials; rejects if user is inactive.
4. System returns `access_token` (short-lived, 30 min) and `refresh_token` (long-lived, 7 days).
5. Client stores tokens securely (secure storage, never localStorage).
6. On 401, client automatically calls `POST /auth/refresh` with `refresh_token`.
7. If refresh fails, client clears tokens and redirects to login.

**Business rules:**
- Passwords must be at least 8 characters with at least one digit and one letter.
- Failed logins do not leak whether it is the username or password that is wrong.
- After password change, existing refresh tokens are invalidated.
- Platform admin uses a separate login path (no school slug required).

---

## 4. School Configuration

### 4.1 School Profile

**Use cases:**
- UC-S1: View school profile
- UC-S2: Update school name, city, legal name, NIF, currency
- UC-S3: Upload school logo
- UC-S4: View school statistics dashboard

**Business rules:**
- Only `school_admin` can update the school profile.
- Logo must be JPEG, PNG, or WebP; maximum 5 MB.
- Currency change applies immediately to all new invoices; existing invoices retain their original currency.
- All authenticated users (any role) can read `GET /schools/info` to display school name, logo, currency in the UI.

### 4.2 School Years

**Use cases:**
- UC-SY1: Create a school year (e.g. "2025/2026")
- UC-SY2: List school years
- UC-SY3: Activate a school year (only one can be active at a time)
- UC-SY4: Update a school year's dates or label

**Workflow:**
1. Admin creates school year with `year_label`, `start_date`, `end_date`.
2. New years default to `is_active = false`.
3. Admin activates a year; the system deactivates all other years for the school.
4. Many records (expenses, invoices, enrollments) reference the active school year.

**Business rules:**
- `start_date` must be before `end_date`.
- A school can have multiple years but only one active.
- Deactivating a year does not delete its records.

---

## 5. People Management

### 5.1 Children

**Use cases:**
- UC-C1: Register a new child
- UC-C2: View child profile (personal data, health, guardians, enrollment)
- UC-C3: Update child information
- UC-C4: Upload child photo
- UC-C5: Deactivate (soft delete) a child
- UC-C6: Link a guardian to a child
- UC-C7: Unlink a guardian from a child

**Data captured per child:**
- Identity: `cedula` (unique per school), first/middle/last name, date of birth, place of birth, sex, nationality
- Health: height, special needs (text), medical prescription
- Address: street, house number, building, apartment, city, município, bairro
- Emergency contact: name + phone
- Photo URL
- Active status

**Workflow — Registering a child:**
1. Admin enters cedula, name, DOB, and optionally all other fields.
2. System validates cedula is unique within the school.
3. Child is created with `is_active = true`.
4. Admin then links guardians (see UC-G4) and creates an enrollment (see UC-E1).

**Business rules:**
- `cedula` is the national identity document number for the child (Angola). Must be unique per school.
- A child can have multiple guardians; exactly one must be marked `is_primary_contact = true`.
- **An enrollment cannot be set to `active` status unless the child has at least one linked guardian with `is_primary_contact = true`.** The API returns 422 if this constraint is violated. An active enrollment without a reachable guardian is a liability risk.
- Deactivated children do not appear in attendance, class lists, or active enrollment views.
- Teachers can view children enrolled in their assigned classes. Admins see all children.
- Parents see only their own linked children.

### 5.2 Guardians

**Use cases:**
- UC-G1: Register a new guardian
- UC-G2: View guardian profile
- UC-G3: Update guardian information
- UC-G4: Link a guardian to a child with relationship type
- UC-G5: Unlink a guardian from a child
- UC-G6: Reset guardian password
- UC-G7: Delete guardian (only if no linked children)

**Data captured per guardian:**
- Identity: first/middle/last name, DOB, place of birth, sex, civil state, nationality, NIF
- ID: id_card_number
- Profession: profession, qualifications
- Address: street, house number, building, apartment, city, município, bairro
- Contact: mobile_first, mobile_second, email
- Photo URL

**Relationship types:** `father`, `mother`, `legal_guardian`, `grandparent`, `other`

**Business rules:**
- Creating a guardian automatically creates a linked user account with role `parent`.
- Guardian username is set by the admin and used for the parent app login.
- Only `school_admin` can reset guardian passwords.
- A guardian can be linked to multiple children (e.g., siblings).

### 5.3 Employees

**Use cases:**
- UC-EM1: Hire a new employee
- UC-EM2: View employee profile
- UC-EM3: Update employee information
- UC-EM4: Upload employee photo
- UC-EM5: Deactivate an employee
- UC-EM6: Reset employee password

**Employee types:** `teacher`, `staff`, `admin`

**Data captured per employee:**
- Personal: first name, last name, employee type, status (active/inactive)
- Contact: email, mobile
- Photo URL
- Linked user account (for login)

**Business rules:**
- Creating an employee automatically creates a linked user account with role matching their employee type (`teacher` → role `teacher`, `staff` → role `staff`, `admin` → role `school_admin`).
- Deactivating an employee also deactivates their user account.
- An `admin`-type employee gets `school_admin` role and full access.
- Deactivated employees do not appear in class assignment dropdowns.

**Password reset hierarchy:**
| User being reset | Who can reset |
|-----------------|---------------|
| `teacher` / `staff` | `school_admin` |
| `school_admin` | Another `school_admin` in the same school, or `platform_admin` |
| `platform_admin` | Only via direct database access (break-glass procedure) |
| `parent` (guardian) | `school_admin` |

A `school_admin` cannot reset their own password via the admin panel — they must use the change-password endpoint (requires knowing the current password) or request a reset from another `school_admin` or the `platform_admin`.

---

## 6. Academic Management

### 6.1 Turmas (Classes)

**Use cases:**
- UC-T1: Create a turma (class/group)
- UC-T2: List all turmas
- UC-T3: Update turma details
- UC-T4: Delete a turma (only if no active enrollments)

**Turma levels:** `Berçário` (0–12 months), `Creche` (1–3 years), `Jardim` (3–6 years)

**Data per turma:** name, level, room, max_capacity

**Business rules:**
- Turma capacity is advisory only — the system warns but does not block over-enrollment.
- A turma is associated with a school year implicitly through its enrollments.

### 6.2 Schedules

**Use cases:**
- UC-SC1: Create a weekly schedule for a turma
- UC-SC2: Add time slots to a schedule (day + time + activity)
- UC-SC3: Assign teachers to a schedule
- UC-SC4: View a turma's full weekly schedule

**Data per schedule:** turma, school year, `effective_from` date, `effective_to` date (nullable), list of slots (day 0–6, time, activity), list of assigned teachers

**Business rules:**
- A turma can have multiple schedules per school year, each with a non-overlapping `effective_from` / `effective_to` range. This allows timetable changes mid-year (e.g. new semester) without destroying the historical record.
- The *active* schedule for a turma on a given date is the one where `effective_from <= date` and (`effective_to` is null or `effective_to >= date`).
- When creating a new schedule for a turma, the system automatically closes the previous schedule by setting its `effective_to = effective_from_of_new_schedule - 1 day`.
- A teacher can be assigned to multiple schedules (different turmas or overlapping periods).
- Activities must exist before they can be added to a slot.
- Historical schedules (closed ones) are read-only and preserved for audit.

### 6.3 Activities

**Use cases:**
- UC-AC1: Create an activity type (e.g. "Educação Musical", "Natação")
- UC-AC2: List activities
- UC-AC3: Update/delete an activity

### 6.4 Enrollments

**Use cases:**
- UC-E1: Enroll a child in a turma for a school year
- UC-E2: View all enrollments (filterable by year, turma, child, status)
- UC-E3: Update enrollment status
- UC-E4: Withdraw a child (change status to `withdrawn`)

**Enrollment statuses:** `active`, `withdrawn`, `graduated`

**Business rules:**
- A child can only have one active enrollment per school year.
- Enrollment links a child to a schedule (which links to a turma and school year).
- Only active enrollments appear in attendance and caderneta workflows.
- When a school year ends, all active enrollments can be bulk-graduated.

---

## 7. Attendance

### 7.1 Daily Check-In / Check-Out

**Use cases:**
- UC-AT1: View today's attendance summary (total enrolled, checked in, absent)
- UC-AT2: Check in a child (record arrival time)
- UC-AT3: Check out a child (record departure time)
- UC-AT4: Bulk-record attendance for a date (mark multiple children at once)
- UC-AT5: View a child's attendance history with date range
- UC-AT6: View monthly attendance summary across all children

**Workflow — Morning attendance:**
1. Teacher opens attendance screen; sees list of enrolled children with their current day status (derived from attendance logs).
2. For each arriving child, teacher taps check-in → system appends a new `AttendanceLog` entry with `event = 'check_in'` and `event_time = now`.
3. Teacher can mark absent children as `absent` or `excused` (no log entry — a separate status record for the date).
4. For departure, teacher taps check-out → system appends a log entry with `event = 'check_out'`.
5. If a child leaves for a mid-day appointment and returns, the teacher checks them out, then checks them back in later. Both are recorded as separate log entries on the same date.
6. Admin can view summary at any time: total enrolled / checked in / currently on premises / absent.

**Attendance model — log-based:**
- `AttendanceLog`: `id`, `school_id`, `child_id`, `log_date`, `event` (`check_in` | `check_out`), `event_time`, `recorded_by`
- `AttendanceDayStatus`: `id`, `school_id`, `child_id`, `status_date`, `status` (`present` | `absent` | `excused`), `notes`, `recorded_by`
- A child is considered "on premises" if their most recent log entry for the date is `check_in`.
- A child's day summary status (`present`, `absent`, `late`, `excused`) is stored separately in `AttendanceDayStatus` and can be set independently of log entries.

**Attendance statuses (day summary):** `present`, `absent`, `late`, `excused`

**Business rules:**
- Only `teacher` and `school_admin` can record attendance.
- Multiple check-in / check-out log entries per child per date are allowed (supports mid-day exits and returns).
- `late` status is set if the first `check_in` log for the day is after 09:00 (configurable per school in future).
- Bulk attendance is useful at end of day: mark all children with no log entries as `absent`.
- Parents can view their child's attendance history (log entries + daily summary, read-only).
- Monthly summary shows attendance rate per child across a date range (based on `AttendanceDayStatus`).

### 7.2 Employee Absences

**Use cases:**
- UC-AB1: Record an employee absence
- UC-AB2: List absences (by employee, date range, type)
- UC-AB3: Update an absence record
- UC-AB4: Delete an absence record
- UC-AB5: View monthly absence summary for an employee

**Absence types:** `sick`, `personal`, `authorized`, `unauthorized`

**Business rules:**
- Only `school_admin` can record and manage employee absences.
- Absence summary shows total days absent per type per month.

---

## 8. Daily Report (Caderneta)

**Use cases:**
- UC-CD1: Teacher creates a daily report for a child
- UC-CD2: Teacher views and edits their submitted reports
- UC-CD3: Admin views all daily reports (with child and teacher filters)
- UC-CD4: Parent views their child's daily reports

**Data per caderneta entry:**
- Child, teacher, date
- Mood (happy / neutral / sad / cranky)
- Sleep: duration in minutes, quality
- Food intake: how much the child ate at each meal (none/little/half/all)
- Diaper changes: count
- Observations: free text
- Activities: what was done during the day

**Workflow:**
1. Teacher selects child from their class list.
2. Fills in mood, sleep, food intake for each meal (breakfast, snack, lunch, afternoon snack), diaper changes, and observations.
3. Submits report.
4. Parent receives notification and can view the report in the parent app.
5. Teacher can edit a same-day report; cannot edit reports from previous days (admin can).

**Business rules:**
- One caderneta per child per day.
- Teachers can only submit reports for children in their assigned turmas.
- Parents see caderneta entries in chronological order, newest first.
- Report date defaults to today; admin can backfill for any date.

---

## 9. Food Management

### 9.1 Food Items

**Use cases:**
- UC-F1: Create food items (ingredients or dishes)
- UC-F2: List and manage food items

**Food types:** `breakfast`, `snack`, `lunch`

### 9.2 Weekly Menus

**Use cases:**
- UC-M1: Create a weekly menu for a level (Berçário / Creche / Jardim)
- UC-M2: Add daily meal items to the menu (by day of week and meal type)
- UC-M3: View the current active menu for a level
- UC-M4: View menu in the parent app (read-only)

**Workflow:**
1. Admin creates a menu for a level with `start_date` and `end_date`.
2. Admin adds items: for each day (Mon–Fri) and meal type, selects food items.
3. Parents can view the current week's menu in the parent app.

**Business rules:**
- A level can have multiple menus over time, but only one is "current" (based on today's date).
- `GET /food/menus/current?level=Creche` returns the active menu for the level.

### 9.3 Meal Orders

**Use cases:**
- UC-MO1: Parent or admin creates a meal order for a child on a specific date
- UC-MO2: Admin views daily meal order counts

**Business rules:**
- Meal order is linked to a specific child and date.
- Daily counts are used by kitchen staff for meal preparation.

---

## 10. Health

### 10.1 Health Events

**Use cases:**
- UC-HE1: Teacher records a health event for a child
- UC-HE2: Teacher/admin views health events (filterable by child, date range)
- UC-HE3: Teacher marks parent as notified
- UC-HE4: Parent views health events for their children

**Event types:** `fever`, `vomiting`, `diarrhea`, `headache`, `rash`, `injury`, `allergic_reaction`, `other`

**Data per event:**
- Child, recorded by (employee), date, time
- Event type, description
- Temperature (if relevant)
- Medication given (boolean + description)
- Parent notified (boolean), notification time
- Action taken

**Business rules:**
- Teachers can record events for any child in the school (not limited to their class — a child might visit the nurse regardless of class).
- Parents see all health events for their linked children.
- When a serious event is recorded, a notification is automatically sent to the parent.

### 10.2 Immunizations

**Use cases:**
- UC-IM1: Record a vaccination for a child
- UC-IM2: View immunization record for a child
- UC-IM3: Update an immunization record
- UC-IM4: Set due date for next dose
- UC-IM5: Parent views their child's vaccination history

**Data per immunization:** child, vaccine name, date administered, due date for next dose, administered by, dose number, notes

**Business rules:**
- Teachers and admins can manage immunizations.
- Parents can view but not edit immunization records.
- System should surface upcoming due dates (future: reminder notifications).

---

## 11. Incidents

**Use cases:**
- UC-INC1: Teacher reports an incident involving a child
- UC-INC2: Admin views all incidents (filterable by child, date, severity)
- UC-INC3: Update incident with follow-up action
- UC-INC4: Mark parent as notified
- UC-INC5: Parent views incidents for their children

**Severity levels:** `minor`, `moderate`, `serious`

**Data per incident:**
- Child, reported by, date, time
- Severity, description
- Action taken
- Parent notified (boolean), notification time

**Business rules:**
- A `serious` incident automatically triggers a push notification to the parent.
- Teachers can report incidents for any child in the school.
- All incident records are permanent (no delete for non-admin).

---

## 12. Evaluations

**Use cases:**
- UC-EV1: Teacher creates a child evaluation
- UC-EV2: Admin/teacher views all evaluations for a child
- UC-EV3: Teacher updates an evaluation
- UC-EV4: Parent views their child's evaluations

**Evaluation categories:** `cognitive`, `social`, `motor_skills`, `language`, `emotional`, `creativity`

**Data per evaluation:** child, teacher, date, category, score (1–5), notes

**Business rules:**
- Teachers can only evaluate children in their assigned turmas.
- Multiple evaluations per child per category are allowed over time (progress tracking).
- Parents see evaluations in read-only mode.

---

## 13. Communication

### 13.1 Announcements

**Use cases:**
- UC-AN1: Create an announcement targeted at a specific audience
- UC-AN2: Pin an announcement (shows at top)
- UC-AN3: Set an expiry date (announcement auto-hides after expiry)
- UC-AN4: Attach a file to an announcement
- UC-AN5: All users view announcements relevant to their role
- UC-AN6: Update or delete an announcement

**Target audiences:** `all`, `parents`, `teachers`

**Workflow:**
1. Teacher or admin creates announcement with title, body, target, optional attachment, optional expiry.
2. All users whose role matches the target see the announcement.
3. Pinned announcements always appear first.
4. Expired announcements are hidden from the list (but not deleted).

**Business rules:**
- Teachers and admins can create announcements.
- Staff can only view announcements, not create.
- Parents see only announcements targeted `all` or `parents`.
- Teachers see `all` or `teachers`.

### 13.2 Messages (Direct)

**Use cases:**
- UC-MSG1: User creates a direct message thread with another user
- UC-MSG2: User sends a message in a thread
- UC-MSG3: User views message threads with unread counts
- UC-MSG4: User reads messages in a thread (marks thread as read)

**Workflow:**
1. Parent selects a teacher from the list and starts a thread.
2. Both parties send and receive messages in the thread.
3. Unread count shown on the messages icon in navigation.
4. Thread is marked read when user opens it.

**Business rules:**
- A thread is between exactly two users (direct messages, not group chat).
- Admin can start threads with any user.
- Parents can start threads with teachers or admins only.
- Teachers can start threads with parents or other staff.
- Messages cannot be deleted (chat history is permanent).

### 13.3 Broadcast Messages

**Use cases:**
- UC-BC1: Admin sends a broadcast to all users, all parents, or all teachers
- UC-BC2: Recipients receive notification about broadcast

**Business rules:**
- Only `school_admin` can send broadcasts.
- Broadcasts create a notification for each recipient; they are not a message thread.

---

## 14. Events

**Use cases:**
- UC-EV1: Admin or teacher creates a school event
- UC-EV2: All users view upcoming events
- UC-EV3: Update or delete an event

**Data per event:** title, description, start_date, end_date, location

**Business rules:**
- Teachers and admins can create events.
- All school users can view events.
- Past events remain visible (not auto-deleted).

---

## 15. Notifications

**Use cases:**
- UC-NF1: User views their notification list
- UC-NF2: User sees unread notification count (badge)
- UC-NF3: User marks all notifications as read
- UC-NF4: User marks a single notification as read

**Notification triggers (system-generated):**
- New caderneta entry → notify parent
- Serious incident → notify parent
- Health event recorded → notify parent (if `parent_notified = true`)
- New announcement → notify targeted users
- Invoice overdue → notify parent
- Trip authorization request → notify parent
- Appointment request → notify target employee

**Business rules:**
- Notifications are per-user and school-isolated.
- A notification can be marked read individually or all at once.
- Unread count drives the badge on the notification bell icon.

---

## 16. Authorizations

### 16.1 Pickup Authorizations

**Use cases:**
- UC-PA1: Admin or parent adds an authorized pickup person for a child
- UC-PA2: Admin views all authorized pickup persons
- UC-PA3: Update or remove an authorized pickup person

**Data per authorization:** child, authorized person name, mobile number, relationship

**Business rules:**
- Only persons on the authorization list should be permitted to pick up a child.
- Teachers can view the list for their class children.
- Multiple authorized persons per child are allowed.

### 16.2 Trip Authorizations

**Use cases:**
- UC-TA1: Admin or teacher creates a trip authorization request for a child
- UC-TA2: Parent receives notification and responds (approve / deny)
- UC-TA3: Admin views all trip requests and their response status
- UC-TA4: Teacher views trip requests for their class

**Data per request:** child, destination, trip date, description, parent response (pending / approved / denied), response date

**Workflow:**
1. Admin creates trip request with child, destination, date, and description.
2. Parent receives notification.
3. Parent opens the request in the app and taps Approve or Deny.
4. Admin sees updated status.

**Business rules:**
- A trip request can only be responded to once (no changing after response).
- Unanswered requests remain `pending`.
- Admin can cancel a pending request.

---

## 17. Documents Library

**Use cases:**
- UC-DL1: Admin uploads a document to the shared library
- UC-DL2: All authenticated users view and download shared documents
- UC-DL3: Admin deletes a document

**Data per document:** name, file URL, uploaded by, upload date, description

**Business rules:**
- Supported file types: PDF, images. Maximum 5 MB per file.
- Documents are school-scoped (not per-child).
- All school users can access the documents library.

---

## 18. Photos

**Use cases:**
- UC-PH1: Teacher or admin uploads a photo (linked to a child or album)
- UC-PH2: All users browse the photo gallery
- UC-PH3: Parent views photos of their children
- UC-PH4: Admin/teacher deletes a photo

**Business rules:**
- Photos can be linked to a specific child (private, only the child's parents see it) or to the school (shared gallery, all see it).
- Image formats: JPEG, PNG, WebP. Maximum 5 MB.

---

## 19. Appointments

**Use cases:**
- UC-AP1: Parent requests an appointment with a specific employee
- UC-AP2: Employee views their incoming appointment requests
- UC-AP3: Employee approves or denies an appointment
- UC-AP4: Admin views all school appointments
- UC-AP5: Parent cancels a pending appointment
- UC-AP6: Employee cancels an approved appointment

**Data per appointment:** employee (target), parent (requester), title, proposed date, status (pending / approved / denied / cancelled), response notes

**Role-based visibility:**
- `parent` sees only their own appointments.
- `teacher`/`staff` sees appointments where they are the target employee.
- `school_admin` sees all appointments.

**Business rules:**
- Appointment request goes to the employee as a notification.
- Once approved, the appointment date is confirmed.
- A cancelled appointment cannot be reopened.
- Parent can only have one pending appointment per employee at a time (future constraint).

---

## 20. Finance Module - Software Requirements Specification

> **Regulatory baseline:** Decreto Presidencial n.o 71/25 de 20 de Marco (Regime Juridico das Facturas) and Decreto Executivo n.o 683/25 de 22 de Agosto (technical specifications). This module targets the certified-software model: local RSA-SHA1 signing + SAF-T (AO) export. Real-time AGT transmission (later phase) is architecturally reserved (see 20.14).

---

### 20.1 Finance Domain Overview

The finance module manages the complete lifecycle of school receivables: from defining what is billable, through issuing legally compliant fiscal documents, collecting payments, managing credit balances, and producing regulatory exports.

**Core domain concepts:**

| Concept | Description |
|---------|-------------|
| Guardian Account | The billing entity. All financial activity is per-guardian, not per-child. |
| Fiscal Document | An AGT-compliant signed document (FT, FR, NC, ND, RC) forming an immutable chain. |
| Payment | Money received from any source, allocated to one or more invoices. |
| Credit Balance | A guardian-level ledger of surplus funds available for future settlement. |
| Cash Session | A daily register discipline for physical cash/check handling. |
| Payment Reference | A Multicaixa (entidade, referencia) pair enabling bank/ATM/mobile payment. |
| Payment Plan | A commercial arrangement restructuring overdue debt into installments. |

**Architectural principles:**

1. **Single document emission point** - All fiscal documents flow through `DocumentEmissionService`. No code path creates a signed document directly.
2. **Single payment convergence point** - All payment processing flows through `PaymentIntakeService`. Whether from admin UI, parent submission, webhook, or credit application.
3. **Immutability** - Financial records are never deleted. Corrections use compensating entries (NC for invoices, reversal for payments).
4. **Guardian-centric billing** - The billing account is the guardian. A child may appear on an invoice line, but the receivable belongs to the guardian.
5. **Fiscal chain integrity** - The RSA-SHA1 signature chain per document series is the audit backbone. Breaking it invalidates all subsequent documents.

---

### 20.2 Domain Model

#### 20.2.1 Aggregate Roots

```
[Guardian Account]
  |-- Invoices (FT, FR, ND)
  |-- Credit Notes (NC, always references an Invoice)
  |-- Payments (allocated to Invoices)
  |-- Receipts (RC, always references a Payment)
  |-- Credit Entries (ledger)
  |-- Credit Refunds
  |-- Payment References
  |-- Payment Plans
  |-- Reminder Logs

[Document Series]
  |-- Per school, per document type, per year
  |-- Controls numbering and hash chain

[Service Catalog]
  |-- Billing Items (the things a school charges for)
  |-- Billing Item Prices (per school year)
  |-- Contracts (recurring billing agreements per child)

[Cash Session]
  |-- Opening/closing register per day

[Expense Tracking]
  |-- Expense Categories
  |-- Expenses (outflows, separate from receivables)
```

#### 20.2.2 Fiscal Document Types

| Type | Name            | Purpose                           | Creates Receivable | Settles Receivable |
|------|-----------------|-----------------------------------|:------------------:|:------------------:|
| `FT` | Factura         | Invoice                           |        Yes         |         No         |
| `FR` | Factura-Recibo  | Invoice + receipt combined        |        Yes         |     Yes (self)     |
| `NC` | Nota de Credito | Credit note (correction downward) |         No         |    Partial/full    |
| `ND` | Nota de Debito  | Debit note (correction upward)    |        Yes         |         No         |
| `RC` | Recibo          | Receipt                           |         No         |        Yes         |

Each type maintains its own series and signature chain per year.

#### 20.2.3 Invoice State Machine

```
                    +-----------+
         emit FT   |  pending  |
         --------> |           |
                    +-----+-----+
                          |
            +-------------+-------------+
            |             |             |
    partial payment   full payment   past due_date
            |             |             |
            v             v             v
    +-------+---+   +----+----+   +----+-----+
    | partially |   |  paid   |   |  overdue  |
    |   _paid   |   |         |   |           |
    +-------+---+   +---------+   +-----+-----+
            |                           |
            +------ full payment -------+
            |             |
            v             v
      +---------+   +---------+
      |  paid   |   |  paid   |
      +---------+   +---------+

    Full NC on any non-paid state -> cancelled
    is_void = true
```

Valid statuses: `pending`, `partially_paid`, `paid`, `overdue`, `cancelled`.

Transitions:
- `pending` -> `partially_paid` (partial payment received)
- `pending` -> `paid` (full payment received)
- `pending` -> `overdue` (due_date passed, daily job)
- `partially_paid` -> `paid` (remaining balance settled)
- `partially_paid` -> `overdue` (due_date passed)
- `overdue` -> `partially_paid` (partial payment)
- `overdue` -> `paid` (full payment)
- Any non-paid -> `cancelled` (full NC issued, is_void=true)

FR documents are created in `paid` status immediately (they are self-settling).

---

### 20.3 AGT Digital Signature Chain

#### 20.3.1 RSA-SHA1 Requirement

AGT certification requires an **RSA-SHA1 asymmetric digital signature**, not a plain hash:

- A SHA-1 hash can be reproduced by anyone; it provides no tamper evidence.
- An RSA-SHA1 signature can only be produced by the private key holder and verified by the public key holder.

#### 20.3.2 Implementation

1. Generate an RSA key pair (2048-bit preferred, 1024-bit minimum).
2. Register the public key with AGT during software certification.
3. Store the private key server-side (environment variable or secrets manager), never in the database, never exposed to clients.
4. For every fiscal document (`FT`, `FR`, `NC`, `ND`, `RC`), sign the canonical string:

```
{InvoiceDate};{SystemEntryDate};{DocumentNumber};{GrossTotal};{PreviousHash}
```

Where:
- `InvoiceDate` = `YYYY-MM-DD`
- `SystemEntryDate` = `YYYY-MM-DDThh:mm:ss` (full ISO 8601, Africa/Luanda timezone)
- `DocumentNumber` = e.g. `FT 2026/1`
- `GrossTotal` = e.g. `12500.00` (exact format below)
- `PreviousHash` = `hash_code` of the previous document in the same series; `"0"` for the first

5. The Base64-encoded signature is stored as `hash_code`. The predecessor's `hash_code` is stored as `previous_hash`.

#### 20.3.3 Chain Integrity Invariants

These are **enforced at the database/service level**, not assumed:

| Invariant | Enforcement |
|-----------|-------------|
| `SystemEntryDate` monotonically non-decreasing within a series | Checked against `last_system_entry_date` on series row |
| `InvoiceDate` >= previous document's `InvoiceDate` in same series | Checked against `last_invoice_date` on series row |
| Sequential gapless numbering | `next_number` on series row, incremented atomically |
| No concurrent emission within a series | `SELECT ... FOR UPDATE` on the series row |
| Signed fields immutable after emission | No UPDATE endpoint exists for these fields |

**Critical operational constraint:** If two processes emit to the same series concurrently without the per-series lock, the chain forks and all subsequent documents are invalid. The lock is mandatory.

#### 20.3.4 Canonical Formatting Rules

A single deviation invalidates every subsequent signature in the chain.

- `GrossTotal`: decimal string, exactly 2 decimal places, `.` as separator, no thousands separator, no currency symbol. Example: `12500.00`
- Rounding: each `line_total` is rounded half-up to 2 decimal places. The document total is the sum of rounded line totals (never round the sum of unrounded values).
- Currency: AOA (Angolan Kwanza). Multi-currency out of scope.
- Timezone: `Africa/Luanda` (WAT, UTC+1, no DST). All `SystemEntryDate` values are generated, stored, and signed in this timezone.
- Server clock discipline (NTP) is an operational requirement. A clock jump backward violates monotonicity.

#### 20.3.5 Key Management

- Private key stored encrypted (env var `AGT_PRIVATE_KEY` or secrets manager), never in database.
- Development: auto-generated ephemeral key at `/tmp/cellen_dev_agt_key.pem`.
- Key compromise or loss requires AGT re-certification and chain restart.
- Key rotation requires AGT re-certification.
- All key operations (generation, rotation, export) write an audit entry (20.12).
- Key material included in encrypted backup routine, stored separately from DB backups.

#### 20.3.6 Signature Excerpt

Every printed document displays a 4-character signature excerpt (characters at positions 1, 11, 21, 31 of the Base64 string). This is the visual anti-tampering indicator per the AGT certification spec. Confirm exact AO positions against DE 683/25.

---

### 20.4 Service Catalog (Billing Items)

#### 20.4.1 Entity: `BillingItem`

The catalog of things a school charges for. Immutable `code` for SAF-T product identification.

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `school_id` | UUID | FK schools |
| `code` | String(20) | Unique per school, immutable after creation |
| `name` | String(100) | Display name |
| `description` | Text | Optional |
| `unit_price` | Numeric(10,2) | Default price (fallback in resolution chain) |
| `iva_rate` | Numeric(5,2) | Default IVA rate |
| `iva_exemption_reason` | String(10) | AGT exemption code (e.g. `M10`) |
| `iva_exemption_legend` | Text | Full legal text for the exemption (printed on documents) |
| `category` | String(50) | For grouping: `tuition`, `meals`, `transport`, `materials`, `activities`, `other` |
| `is_active` | Boolean | Soft-disable (inactive items excluded from new contracts/invoices) |
| `created_at`, `updated_at` | DateTime | |

**Seeded defaults** (created when a school is provisioned):
- `MENSALIDADE` (Tuition), `INSCRICAO` (Enrollment fee), `ALIMENTACAO` (Meals), `TRANSPORTE` (Transport), `MATERIAL` (Materials)

**Business rules:**
- `code` cannot be changed after creation (SAF-T references it).
- Price changes are prospective only; existing invoices retain their issued amounts.
- IVA exemption legend example: `M10` -> "Isento nos termos do artigo 12.o do CIVA" (confirm against current AGT code table during certification).

#### 20.4.2 Entity: `BillingItemPrice`

Per-school-year pricing. Allows tuition to change annually without editing contracts.

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `billing_item_id` | UUID | FK billing_items |
| `school_year_id` | UUID | FK school_years |
| `unit_price` | Numeric(10,2) | Price for this item in this school year |
| `created_at` | DateTime | |

**Price resolution order** (single rule, used everywhere a line is generated):

```
contract.unit_price (explicit override)
  -> BillingItemPrice for the invoice's school_year
    -> BillingItem.unit_price (catalog default)
```

#### 20.4.3 Use Cases

- **UC-BI1:** Admin creates a billing item with code, name, default price, IVA rate.
- **UC-BI2:** Admin updates a billing item (name, price, IVA rate, active status). Code is immutable.
- **UC-BI3:** Admin defines prices per school year (create `BillingItemPrice` entries).
- **UC-BI4:** Admin bulk-rolls prices to new school year: copy previous year + global % increase, then edit per item.
- **UC-BI5:** Admin views price history per item across school years.

---

### 20.5 Contracts

#### 20.5.1 Entity: `Contract`

A recurring billing agreement for one child with one guardian. Drives the bulk invoice generation.

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `school_id` | UUID | FK schools |
| `child_id` | UUID | FK children |
| `billing_guardian_id` | UUID | FK guardians |
| `billing_item_id` | UUID | FK billing_items |
| `school_year_id` | UUID | FK school_years (nullable) |
| `unit_price` | Numeric(10,2) | Override price (nullable = use resolution chain) |
| `quantity` | Numeric(8,2) | Default 1 |
| `discount_percent` | Numeric(5,2) | 0-100, default 0 |
| `discount_amount` | Numeric(10,2) | Absolute discount, default 0 |
| `start_date` | Date | |
| `end_date` | Date | Nullable (open-ended) |
| `status` | String | `active`, `suspended`, `terminated` |
| `notes` | Text | |
| `created_at`, `updated_at` | DateTime | |

**Business rules:**
- At most one of `discount_percent` or `discount_amount` may be non-zero per contract.
- Contracts without a `unit_price` override automatically follow the school-year price table.
- Only `active` contracts with `start_date <= invoice_month <= end_date` are included in bulk generation.
- Suspending a contract excludes it from future bulk generation but does not affect already-issued invoices.

#### 20.5.2 Use Cases

- **UC-CO1:** Admin creates a contract for a child (select guardian, billing item, optional price override, optional discount).
- **UC-CO2:** Admin lists contracts filterable by child, guardian, status, school year.
- **UC-CO3:** Admin updates a contract (price, discount, dates, status).
- **UC-CO4:** Admin terminates a contract (sets end_date and status=terminated).
- **UC-CO5:** Admin views all contracts for a guardian (used in account review).

---

### 20.6 Invoices

#### 20.6.1 Entity: `Invoice`

Holds FT, FR, and ND documents. All share the same table and signature chain structure.

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `school_id` | UUID | FK schools |
| `document_type` | String(5) | `FT`, `FR`, `ND` |
| `series_year` | Integer | Year of the document series |
| `series_number` | Integer | Sequential number within series |
| `full_document_number` | String(30) | e.g. `FT 2026/42`. Unique per school. |
| `invoice_date` | Date | The document date (business day) |
| `system_entry_date` | DateTime | Exact timestamp of creation (used in signature) |
| `due_date` | Date | Payment deadline (nullable for FR) |
| `billing_guardian_id` | UUID | FK guardians (nullable for Consumidor Final) |
| `child_id` | UUID | FK children (nullable, informational) |
| `customer_nif` | String(20) | Guardian's NIF or generic final-consumer NIF |
| `customer_name` | String(200) | |
| `is_final_consumer` | Boolean | True if issued to Consumidor Final |
| `gross_total` | Numeric(12,2) | Sum of rounded line totals |
| `net_total` | Numeric(12,2) | Sum of line nets |
| `iva_total` | Numeric(12,2) | Sum of line IVA amounts |
| `hash_code` | Text | RSA-SHA1 signature (Base64) |
| `previous_hash` | Text | Hash of previous document in same series |
| `status` | String(20) | See state machine (20.2.3) |
| `is_void` | Boolean | True when fully credited by NC |
| `void_reason` | Text | Reason for voiding |
| `description` | Text | Header description |
| `reference_month` | Date | The month this invoice covers (for grouping) |
| `notes` | Text | Internal notes |
| `corrected_invoice_id` | UUID | FK invoices (for ND: which FT it corrects) |
| `correction_reason` | Text | Why the correction was issued |
| `issued_by` | UUID | FK users |
| `school_year_id` | UUID | FK school_years |
| `transmission_status` | String(20) | `not_required`, `pending`, `transmitted`, `rejected` |
| `transmission_response` | JSONB | AGT response when transmitted |
| `created_at`, `updated_at` | DateTime | |

#### 20.6.2 Entity: `InvoiceLine`

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `invoice_id` | UUID | FK invoices |
| `line_number` | Integer | Sequential within invoice |
| `billing_item_id` | UUID | FK billing_items (nullable for ad-hoc lines) |
| `description` | String(200) | Line description |
| `quantity` | Numeric(8,2) | |
| `unit_price` | Numeric(10,2) | |
| `discount_percent` | Numeric(5,2) | 0-100 |
| `discount_amount` | Numeric(10,2) | Absolute |
| `iva_rate` | Numeric(5,2) | |
| `iva_exemption_reason` | String(10) | AGT code |
| `iva_exemption_legend` | Text | Full legal text |
| `line_net` | Numeric(10,2) | `unit_price * quantity - discount` |
| `iva_amount` | Numeric(10,2) | `line_net * iva_rate / 100` |
| `line_total` | Numeric(10,2) | `line_net + iva_amount` (rounded half-up) |
| `credited_amount` | Numeric(10,2) | Cumulative amount credited by NC(s) |

**Line computation:**
```
discount = max(discount_percent/100 * unit_price * quantity, discount_amount)
line_net = (unit_price * quantity) - discount
iva_amount = line_net * (iva_rate / 100)
line_total = round(line_net + iva_amount, 2, ROUND_HALF_UP)
```

At most one of `discount_percent` or `discount_amount` may be non-zero.

#### 20.6.3 Consumidor Final

- System maintains one built-in "Consumidor Final" customer per school with generic NIF (`999999999` - confirm AO value in DE 683/25).
- School-level setting: `allow_final_consumer_invoicing` (default off for bulk, on for counter FR).
  - **Off:** bulk generation skips children whose billing guardian has no NIF (reported in warning list).
  - **On:** document issued against Consumidor Final; guardian remains linked internally for account statement purposes.
- Parent-facing app prompts guardians with missing NIF to provide it.
- NC against a Consumidor Final invoice requires attaching a real NIF first (AGT constraint - verify during certification).

#### 20.6.4 Use Cases

- **UC-FI1:** Admin creates a single invoice (FT) for a guardian with ad-hoc lines.
- **UC-FI2:** Admin runs bulk invoice generation for a month:
  1. Select school year and reference month.
  2. System resolves all active contracts for that period.
  3. For each child: resolve price (contract override -> year table -> item default), apply contract discount, create invoice lines.
  4. Skip children without a billing guardian or (if policy off) without guardian NIF. Report in warning list.
  5. Sign and emit all invoices (per-series locking ensures chain integrity even in bulk).
  6. Return summary: count generated, total amount, warnings.
- **UC-FI3:** Admin views invoice list filterable by status, guardian, child, date range, document type.
- **UC-FI4:** Admin views a single invoice with lines, payment history, and associated NC/RC.
- **UC-FI5:** Admin downloads/prints invoice PDF (see 20.4 rendering requirements).
- **UC-FI6:** Admin voids an invoice (full NC, all lines credited - see Credit Notes).
- **UC-FI7:** Admin generates/registers a payment reference for an invoice (delegates to 20.9).
- **UC-FI8:** System marks overdue invoices daily (scheduled job).
- **UC-FI9:** Admin issues a **Factura-Recibo (FR)** for immediate payment:
  - Creates FR document (its own series and chain).
  - Creates Payment record with chosen method.
  - Creates allocation.
  - **No separate RC is generated** (FR is self-settling).
  - FR status is `paid` from creation.
- **UC-FI10:** Admin issues a **partial credit note** (see Credit Notes section).
- **UC-FI11:** Admin issues a **Nota de Debito (ND)**:
  - References an FT (e.g. late fee, correction of under-billing).
  - Increases the guardian's balance.
  - Enters the ND series hash chain.
  - ND participates in balance, aging, and delinquency exactly like FT.

#### 20.6.5 Business Rules

- Invoices are immutable once signed. No field that participates in the signature may be modified.
- An invoice cannot be deleted. It can only be voided via NC (status -> cancelled, is_void=true).
- `reference_month` groups invoices for reporting but does not affect fiscal validity.
- FR documents appear in SAF-T as invoices with an embedded settlement.
- `billing_guardian_id` is the accounting link; `child_id` is informational metadata.

---

### 20.7 Credit Notes (NC)

#### 20.7.1 Entity: `CreditNote`

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `school_id` | UUID | FK schools |
| `invoice_id` | UUID | FK invoices (the corrected document) |
| `series_year` | Integer | |
| `series_number` | Integer | |
| `full_document_number` | String(30) | e.g. `NC 2026/5` |
| `invoice_date` | Date | NC issuance date |
| `system_entry_date` | DateTime | |
| `customer_nif` | String(20) | Copied from original invoice |
| `customer_name` | String(200) | |
| `net_total` | Numeric(12,2) | |
| `iva_total` | Numeric(12,2) | |
| `gross_total` | Numeric(12,2) | |
| `reason` | Text | Mandatory correction reason |
| `lines` | JSONB | Detail of credited lines [{line_id, description, amount}] |
| `hash_code` | Text | RSA-SHA1 signature |
| `previous_hash` | Text | |
| `issued_by` | UUID | FK users |
| `transmission_status` | String(20) | |
| `transmission_response` | JSONB | |
| `created_at` | DateTime | |

#### 20.7.2 Use Cases

- **UC-NC1:** Admin issues a **full void** (all lines, full amounts):
  - All line `credited_amount` set to `line_total`.
  - Original invoice: `is_void=true`, `status=cancelled`.
  - NC `gross_total` = original invoice's remaining uncredited amount.
- **UC-NC2:** Admin issues a **partial credit note**:
  - Selects specific lines and amounts to credit.
  - Constraint: `credited_amount + new_credit <= line_total` per line.
  - Original invoice remains valid for the uncredited remainder.
  - Invoice balance and status are recomputed.

#### 20.7.3 Business Rules

- NC always references exactly one invoice.
- NC `gross_total` = sum of credited amounts (which may be less than original invoice total for partial NC).
- Cumulative credited amount per line cannot exceed original line total.
- NC is signed in the NC series chain (separate from FT chain).
- NC against Consumidor Final invoice requires a real NIF first.
- NC prints reference to corrected document (e.g. "Rectifica FT 2026/42") and reason.
- NC reduces the guardian's receivable balance by `gross_total`.

---

### 20.8 Payments

#### 20.8.1 Entity: `Payment`

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `school_id` | UUID | FK schools |
| `billing_guardian_id` | UUID | FK guardians |
| `received_by` | UUID | FK users (who recorded it) |
| `payment_date` | Date | When the money was received |
| `amount` | Numeric(12,2) | Total amount received |
| `payment_method` | String(30) | See below |
| `notes` | Text | |
| `receipt_proof_url` | String(500) | Uploaded proof (scan/photo) |
| `idempotency_key` | String(100) | Unique per school (nullable) |
| `payment_reference_id` | UUID | FK payment_references (nullable) |
| `cash_session_id` | UUID | FK cash_sessions (nullable) |
| `status` | String(20) | `normal`, `reversed` |
| `reverse_reason` | Text | |
| `reversed_at` | DateTime | |
| `created_at` | DateTime | |

**Payment methods:**
- `cash` - Physical cash (requires open cash session)
- `check` - Bank check (requires open cash session)
- `bank_transfer` - Wire transfer / TPA
- `multicaixa_ref` - Paid via Multicaixa reference
- `multicaixa_express` - Paid via MCX Express (future)
- `credit` - Credit balance application (internal, never user-selectable for real money)
- `other` - Catch-all

#### 20.8.2 Entity: `PaymentAllocation`

Links a payment to the invoices it settles.

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `payment_id` | UUID | FK payments |
| `invoice_id` | UUID | FK invoices |
| `amount_applied` | Numeric(12,2) | How much of this payment goes to this invoice |
| `created_at` | DateTime | |

#### 20.8.3 Allocation Logic

Two modes:

1. **Explicit targeting** - Payment specifies target invoice(s). Allocates to each in order until exhausted.
2. **Oldest-first** - No target specified. System finds all open FT/ND invoices for the guardian, ordered by `invoice_date ASC`, and allocates sequentially.

In both modes, if the payment amount exceeds all open balances, the surplus creates a `CreditEntry` (see 20.10).

#### 20.8.4 Idempotency

- `idempotency_key` unique per school. A retry with the same key returns the original payment without creating a duplicate.
- `payment_reference_id` unique on Payment table. One payment per reference, ever.
- These guards are mandatory in v1 - they protect against admin double-clicks and future webhook retries.

#### 20.8.5 Use Cases

- **UC-PA1:** Admin records a payment for a guardian (manual entry: amount, method, date, optional target invoice).
- **UC-PA2:** Payment arrives via PaymentReference mark-paid (manual) or webhook (API mode).
- **UC-PA3:** Credit balance is applied to an invoice (creates a `credit` method payment).
- **UC-PA4:** Admin views payment list filterable by guardian, method, date range, status.
- **UC-PA5:** Admin reverses a payment (see reversal rules below).
- **UC-PA6:** Admin uploads payment proof (receipt scan/photo).

#### 20.8.6 Payment Reversal

Workflow:
1. Validate payment exists and is not already reversed.
2. Check if any CreditEntry from this payment's surplus has been partially/fully applied. If yes, **block reversal** until credit application is reversed first (ordered unwinding, no cascading changes).
3. Mark payment `status=reversed`, record reason and timestamp.
4. Mark associated RC as `status=A` (Anulado) with reversal date and reason.
5. If payment was reference-originated: return PaymentReference to `active` (if not expired) or `cancelled` (if expired).
6. Recalculate affected invoice statuses.
7. Write audit entry.

**SAF-T mapping:** Reversed RC exported with status `A` (Anulado).

---

### 20.9 Receipts (RC)

#### 20.9.1 Entity: `Receipt`

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `school_id` | UUID | FK schools |
| `payment_id` | UUID | FK payments |
| `series_year` | Integer | |
| `series_number` | Integer | |
| `full_document_number` | String(30) | e.g. `RC 2026/15` |
| `invoice_date` | Date | Receipt date |
| `system_entry_date` | DateTime | |
| `customer_nif` | String(20) | |
| `customer_name` | String(200) | |
| `gross_total` | Numeric(12,2) | = payment amount |
| `settled_documents` | JSONB | [{invoice_id, document_number, amount_applied}] |
| `hash_code` | Text | RSA-SHA1 signature |
| `previous_hash` | Text | |
| `status` | String(5) | `N` (normal) or `A` (Anulado) |
| `reversal_date` | Date | When reversed |
| `reversal_reason` | Text | |
| `issued_by` | UUID | FK users |
| `transmission_status` | String(20) | |
| `transmission_response` | JSONB | |
| `created_at` | DateTime | |

#### 20.9.2 Business Rules

- One RC is generated per payment (via `PaymentIntakeService`).
- FR documents do NOT generate a separate RC (they embed the settlement).
- RC is signed in the RC series chain.
- A reversed RC retains its position in the chain with status `A`.
- RC `gross_total` = the payment amount (not necessarily the sum of settled documents if there's surplus).

---

### 20.10 Payment References (Multicaixa)

#### 20.10.1 Overview

Angola's Multicaixa ecosystem provides two payment rails:

1. **Pagamento por Referencia** - An (entidade, referencia) pair payable at ATMs, internet banking, or Multicaixa Express. Obtained from EMIS via a licensed gateway or manually from the school's bank portal.
2. **Multicaixa Express direct** - App-push payment. Out of scope for v1; architecture reserved.

v1 operates in **manual mode**: admin obtains references from their bank portal and registers them in the system.

#### 20.10.2 Entity: `PaymentReference`

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `school_id` | UUID | FK schools |
| `invoice_id` | UUID | FK invoices (nullable for guardian-level open-amount) |
| `billing_guardian_id` | UUID | FK guardians (always set) |
| `entity` | String(10) | Multicaixa entity number (5 digits) |
| `reference` | String(20) | 9-digit reference |
| `amount` | Numeric(12,2) | Locked amount (nullable = open amount) |
| `status` | String(20) | `active`, `paid`, `expired`, `cancelled` |
| `expires_at` | DateTime | |
| `provider` | String(20) | `manual`, `proxypay`, `appypay`, `emis_gpo` |
| `external_id` | String(100) | Provider-side identifier (null for manual) |
| `created_by` | UUID | FK users |
| `paid_at` | DateTime | When marked paid |
| `created_at` | DateTime | |

#### 20.10.3 Provider Abstraction (Protected Variations)

```
PaymentReferenceProvider (interface)
  create_reference(guardian, invoice?, amount?, expires_at) -> {entity, reference, external_id}
  cancel_reference(reference) -> void

  +-- ManualProvider       # v1: admin supplies entity/reference from bank portal
  +-- ProxyPayProvider     # v2: API + webhook
  +-- AppyPayProvider      # v2: API + webhook
  +-- EmisGpoProvider      # v2: API + webhook / token
```

Provider is a school-level configuration. Switching provider affects only how references are created and how paid-notifications arrive. Nothing downstream changes.

#### 20.10.4 Use Cases

- **UC-MR1:** Admin generates (API mode) or registers (manual mode) a payment reference for an invoice.
- **UC-MR2:** Admin marks a reference as paid (date, amount, optional proof). This is manual-mode intake - calls the same `PaymentIntakeService.intake()` that a future webhook will call.
- **UC-MR3:** Webhook endpoint receives a provider paid-notification (API mode). Signature verification per provider; unverifiable callbacks stored quarantined, never processed.
- **UC-MR4:** Admin cancels a reference. System auto-expires references past `expires_at` (daily job).
- **UC-MR5:** Admin runs reconciliation: compares bank/EMIS settlement report against system state. Identifies discrepancies (paid at bank but not in system, marked paid but absent from settlement, amount mismatches). Each resolved explicitly and audit-logged.
- **UC-MR6:** Admin lists references filterable by status, guardian, invoice, date range.

#### 20.10.5 Business Rules

- At most **one `active` reference per invoice**.
- Amount-locked reference must equal the invoice balance at creation time. If balance changes (partial payment, NC), the active reference is automatically cancelled and flagged for regeneration.
- Amount mismatch on payment: shortfall -> invoice `partially_paid`; surplus -> `CreditEntry`.
- References are never deleted. Cancelled/expired retained for reconciliation.
- Late payments to cancelled/expired references are still ingested (money is real) with a warning raised for review.
- Unique constraint on (`provider`, `external_id`) prevents duplicate webhook processing.

---

### 20.11 Credit Balances

#### 20.11.1 Entity: `CreditEntry`

A ledger of guardian credit. Balance = sum of `amount_remaining` on non-reversed entries.

| Field                 | Type          | Rules                                                     |
|-----------------------|---------------|-----------------------------------------------------------|
| `id`                  | UUID          | PK                                                        |
| `school_id`           | UUID          | FK schools                                                |
| `billing_guardian_id` | UUID          | FK guardians                                              |
| `source`              | String(30)    | `payment_surplus`, `refund_reversal`, `manual_adjustment` |
| `source_payment_id`   | UUID          | FK payments (nullable)                                    |
| `amount`              | Numeric(12,2) | Original entry amount                                     |
| `amount_remaining`    | Numeric(12,2) | Unconsumed balance                                        |
| `is_reversed`         | Boolean       |                                                           |
| `notes`               | Text          | Mandatory for manual_adjustment                           |
| `created_at`          | DateTime      |                                                           |

#### 20.11.2 Entity: `CreditRefund`

| Field                 | Type          | Rules                        |
|-----------------------|---------------|------------------------------|
| `id`                  | UUID          | PK                           |
| `school_id`           | UUID          | FK schools                   |
| `billing_guardian_id` | UUID          | FK guardians                 |
| `amount`              | Numeric(12,2) |                              |
| `refund_method`       | String(30)    | How the refund was disbursed |
| `reference`           | String(100)   | External reference           |
| `authorized_by`       | UUID          | FK users                     |
| `notes`               | Text          |                              |
| `created_at`          | DateTime      |                              |

#### 20.11.3 Mechanics

**Applying credit (UC-CB2):**
1. Validate requested amount <= guardian's current credit balance.
2. Consume credit entries FIFO (decrement `amount_remaining`).
3. Create a Payment with method `credit` targeting the chosen invoice.
4. Standard allocation and RC generation via `PaymentIntakeService`.
5. Credit applications are fiscally visible (they generate an RC like any other settlement).

**Refunding credit (UC-CB3):**
1. Validate amount <= current balance.
2. Record `CreditRefund` with authorization.
3. Decrement entries FIFO.
4. No RC generated (nothing is being settled).
5. Appears on account statement as informational line.
6. Write audit entry.

**Reversal ordering:**
- Credit applications must be reversed before the payment that created the credit can be reversed.
- This prevents silent cascading balance changes.

#### 20.11.4 Use Cases

- **UC-CB1:** Admin views a guardian's credit balance and movement history.
- **UC-CB2:** Admin applies credit to an outstanding invoice.
- **UC-CB3:** Admin refunds credit to the guardian (money out). Requires `school_admin` role.
- **UC-CB4:** Admin views all guardians with non-zero credit balances.
- **UC-CB5:** Parent views their own credit balance in the app.

#### 20.11.5 Business Rules

- Balance can never go negative. Applications and refunds are capped at current balance.
- Manual adjustments require `school_admin` role and mandatory reason.
- Credit entries are never deleted; corrections use compensating entries.
- Manual adjustment source = `manual_adjustment` (distinguished from system-generated entries).

---

### 20.12 Finance Audit Log

#### 20.12.1 Entity: `FinanceAuditEntry`

Immutable, append-only log.

| Field             | Type       | Rules                   |
|-------------------|------------|-------------------------|
| `id`              | UUID       | PK                      |
| `school_id`       | UUID       | FK schools              |
| `actor_id`        | UUID       | FK users                |
| `timestamp`       | DateTime   |                         |
| `entity_type`     | String(50) | What was affected       |
| `entity_id`       | UUID       |                         |
| `action`          | String(50) | What happened           |
| `before_snapshot` | JSONB      | State before (nullable) |
| `after_snapshot`  | JSONB      | State after (nullable)  |
| `reason`          | Text       |                         |

#### 20.12.2 Mandatory Triggers

| Action                              | entity_type             | action value               |
|-------------------------------------|-------------------------|----------------------------|
| Invoice voided (full NC)            | invoice                 | void                       |
| NC issued (partial or full)         | credit_note             | issue                      |
| ND issued                           | invoice                 | issue_nd                   |
| Payment reversal                    | payment                 | reverse                    |
| Credit application                  | credit_entry            | apply_credit               |
| Credit refund                       | credit_entry            | refund                     |
| Manual credit adjustment            | credit_entry            | manual_adjustment          |
| Price change (item/table/contract)  | billing_item / contract | price_change               |
| Cash session close (variance > 0)   | cash_session            | close_variance             |
| Cash session reopen                 | cash_session            | reopen                     |
| Reference reconciliation resolution | payment_reference       | reconcile                  |
| SAF-T export                        | saft_export             | export                     |
| AGT key operation                   | agt_key                 | generate / rotate / export |
| Role grant/revoke                   | user                    | role_change                |

#### 20.12.3 Rules

- Entries are never edited or deleted.
- Retention follows DP 71/25 conservation rules (minimum 10 years for fiscal documents).
- UC-AL1: Admin views/filters the audit log by entity, actor, action, date range.

---

### 20.13 Cash Sessions (Fecho de Caixa)

#### 20.13.1 Entity: `CashSession`

| Field                | Type          | Rules                           |
|----------------------|---------------|---------------------------------|
| `id`                 | UUID          | PK                              |
| `school_id`          | UUID          | FK schools                      |
| `opened_by`          | UUID          | FK users                        |
| `opened_at`          | DateTime      |                                 |
| `opening_float`      | Numeric(12,2) | Cash in drawer at start         |
| `closed_by`          | UUID          | FK users (nullable)             |
| `closed_at`          | DateTime      | (nullable)                      |
| `expected_by_method` | JSONB         | System-computed expected totals |
| `counted_by_method`  | JSONB         | Officer-entered counted amounts |
| `variance`           | Numeric(12,2) | counted - expected (nullable)   |
| `variance_reason`    | Text          | Required if variance != 0       |
| `status`             | String(10)    | `open`, `closed`                |
| `created_at`         | DateTime      |                                 |

#### 20.13.2 Use Cases

- **UC-CS1:** Finance officer opens a session (records opening float).
- **UC-CS2:** Cash/check payments during the day attach to the open session automatically.
- **UC-CS3:** Officer closes session: system shows expected totals per method; officer enters counted amounts; variance computed; justification required if non-zero.
- **UC-CS4:** Admin views session history and variance report.
- **UC-CS5:** Admin reopens a closed session (exceptional; mandatory reason; audit-logged).

#### 20.13.3 Business Rules

- At most one open session per school at a time (v1; multi-register is a future variation).
- `cash` and `check` payments **require** an open session. The system auto-attaches them.
- Other payment methods (transfer, multicaixa) do not require a session.
- Payments cannot be added to a closed session. Late entries go to the next session with a note.
- Closing computes: `expected_by_method` = sum of payments in this session grouped by method.

---

### 20.14 AGT Electronic Transmission Layer (Reserved)

DP 71/25 mandates real-time electronic invoicing in phases. This architecture ensures it's a plug-in, not a rewrite:

1. All document emission flows through `DocumentEmissionService`. No code path creates a signed document directly.
2. `TransmissionProvider` interface:
   - v1: `none` (documents emitted locally, reported via SAF-T only)
   - Future: `agt_einvoice` implementation per DE 683/25
3. Each document carries `transmission_status` and `transmission_response`.
4. A retry queue handles AGT unavailability (emission is never blocked by transmission - the a-posteriori validation model permits this).
5. Phase-in dates tracked per school. Provider switch is configuration-only.

---

### 20.15 Payment Plans (Acordo de Pagamento)

#### 20.15.1 Entity: `PaymentPlan`

| Field                 | Type          | Rules                                          |
|-----------------------|---------------|------------------------------------------------|
| `id`                  | UUID          | PK                                             |
| `school_id`           | UUID          | FK schools                                     |
| `billing_guardian_id` | UUID          | FK guardians                                   |
| `covered_invoice_ids` | JSONB         | List of invoice UUIDs covered                  |
| `status`              | String(20)    | `active`, `completed`, `breached`, `cancelled` |
| `total_amount`        | Numeric(12,2) | Sum of covered invoice balances at creation    |
| `created_by`          | UUID          | FK users                                       |
| `notes`               | Text          |                                                |
| `created_at`          | DateTime      |                                                |

#### 20.15.2 Entity: `PaymentPlanInstallment`

| Field                | Type          | Rules                      |
|----------------------|---------------|----------------------------|
| `id`                 | UUID          | PK                         |
| `plan_id`            | UUID          | FK payment_plans           |
| `installment_number` | Integer       |                            |
| `due_date`           | Date          |                            |
| `amount`             | Numeric(12,2) |                            |
| `status`             | String(10)    | `pending`, `met`, `missed` |
| `paid_at`            | Date          | When marked met            |
| `created_at`         | DateTime      |                            |

#### 20.15.3 Use Cases

- **UC-PP1:** Admin creates a payment plan: selects guardian, overdue invoices, defines N installments with dates and amounts.
- **UC-PP2:** Admin lists plans filterable by status, guardian.
- **UC-PP3:** System matches incoming guardian payments against plan installments (marks them `met`).
- **UC-PP4:** Daily job: flags plans `breached` when an installment passes its due date unmet. Admin may cancel or renegotiate.

#### 20.15.4 Business Rules

- Installment totals must equal the covered invoices' combined balance at plan creation.
- **Delinquency interaction:** invoices covered by an `active` plan report against installment schedule, not original due dates. On breach, they revert to original aging immediately.
- A plan is a commercial arrangement. It creates no fiscal documents and never modifies invoices.
- Only `school_admin` can create/modify plans.

---

### 20.16 Dunning (Payment Reminders)

#### 20.16.1 Entity: `ReminderLog`

| Field                 | Type       | Rules                                          |
|-----------------------|------------|------------------------------------------------|
| `id`                  | UUID       | PK                                             |
| `school_id`           | UUID       | FK schools                                     |
| `billing_guardian_id` | UUID       | FK guardians                                   |
| `invoice_ids`         | JSONB      | Referenced invoices                            |
| `level`               | Integer    | 1, 2, 3 (escalation)                           |
| `channel`             | String(20) | `whatsapp`, `email`, `sms`, `letter`, `verbal` |
| `sent_by`             | UUID       | FK users                                       |
| `sent_at`             | DateTime   |                                                |
| `message_snapshot`    | Text       | The actual message text sent                   |
| `created_at`          | DateTime   |                                                |

#### 20.16.2 Use Cases

- **UC-DN1:** Admin generates reminder messages from templates with merge fields (guardian name, children, open documents, total, payment reference). Templates in Portuguese.
- **UC-DN2:** Admin marks reminders as sent, recording channel. v1 sending is manual (copy/print); the log is the system of record.
- **UC-DN3:** Admin views reminder history per guardian and effectiveness report (reminders sent vs. subsequent payment).

#### 20.16.3 Business Rules

- Escalation order enforced: level 2 only after level 1, etc.
- Minimum interval between levels is configurable (school setting).
- Guardians with an `active` payment plan are excluded from dunning for covered invoices.
- Reminder levels: 1 = friendly reminder, 2 = formal notice, 3 = final notice / pre-legal.

---

### 20.17 Guardian Account Statement (Extrato de Conta)

The single most-requested artifact: one chronological view of everything a guardian owes and has paid, with a running balance.

#### 20.17.1 Content

Chronological movements with running balance:

| Movement | Debit (increases balance) | Credit (decreases balance) |
|----------|:---:|:---:|
| FT issued | gross_total | - |
| ND issued | gross_total | - |
| FR issued | gross_total | gross_total (net 0) |
| NC issued | - | gross_total |
| Payment / RC | - | amount |
| Credit application | - | amount |
| Payment reversal | original amount | - |
| Credit refund | - | - (informational only) |

**Header:** total invoiced, total settled, current balance, current credit balance, oldest open document.

#### 20.17.2 Use Cases

- **UC-AS1:** Admin views/prints a guardian's account statement for a period or school year.
- **UC-AS2:** Parent views their own statement in the app.
- **UC-AS3:** Admin filters by child (metadata filter - the account is per guardian).

#### 20.17.3 Rules

- PDF export follows school branding. It is NOT a fiscal document (no signature, clearly labelled "Extrato de Conta").
- Statement period defaults to current school year if not specified.
- Running balance starts at 0 for the selected period (or shows carry-forward from prior period).

---

### 20.18 Document Rendering Requirements

Stored data alone is not sufficient. The rendered document (PDF/print) has mandatory content per AGT:

1. **Issuer identification:** school legal name, NIF, address, IVA regime.
2. **Customer identification:** guardian name, NIF, billing address. Or Consumidor Final convention when applicable.
3. **Document header:** full document number, `InvoiceDate`, due date (FT), payment method (FR/RC).
4. **Line items:** description, quantity, unit price, discount, IVA rate, line total.
5. **Totals:** net total, IVA total, gross total.
6. **IVA exemption legend** in full text per line or in footer (per AGT layout rules).
7. **Certification mention:** "Processado por programa validado n.o ___/AGT" + 4-char signature excerpt.
8. **Reprints** marked as "2.a via".
9. **NC/ND** must print reference to corrected document and correction reason.
10. **RC** must list settled documents with amounts.

---

### 20.19 Finance Reports

#### 20.19.1 Dashboard KPIs

- Total outstanding (open receivables)
- Total collected this month
- Total overdue
- Number of overdue guardians
- Revenue vs. expenses (month)
- Credit balances total
- Open cash session indicator
- Invoices generated this month (count + amount)
- Collection rate (% of invoiced amount collected)

#### 20.19.2 Report Types

| Report | Description |
|--------|-------------|
| P&L Monthly | Income (payments received) vs. expenses by category |
| P&L Annual | Monthly breakdown for a year |
| Outstanding Invoices | All unpaid/overdue with guardian, days overdue, balance |
| Delinquent Guardians | Grouped by guardian with total owed, aging buckets |
| Cash Flow | Monthly receipts vs. disbursements over period |
| Account Statement | Per guardian (see 20.17) |
| SAF-T Export | Full regulatory export (see 20.19.3) |

#### 20.19.3 SAF-T (AO) Export

Complete XML export conforming to the SAF-T (AO) schema:

**Structure:**
```xml
<AuditFile>
  <Header>
    <AuditFileVersion>1.01_01</AuditFileVersion>
    <CompanyID>{school_nif}</CompanyID>
    <TaxRegistrationNumber>{school_nif}</TaxRegistrationNumber>
    ...fiscal year, periods, company info...
  </Header>
  <MasterFiles>
    <Customer> ...one per guardian + Consumidor Final if used... </Customer>
    <Product> ...one per BillingItem... </Product>
  </MasterFiles>
  <SourceDocuments>
    <SalesInvoices>
      ...all FT, FR, ND documents in period...
      ...NC as CreditNotes...
    </SalesInvoices>
    <Payments>
      ...all RC documents in period...
      ...reversed RCs with status A...
    </Payments>
  </SourceDocuments>
</AuditFile>
```

**Business rules for SAF-T:**
- Export period: fiscal year or date range.
- Include Consumidor Final customer when referenced by documents in period.
- ND documents in `SalesInvoices` with appropriate type code.
- FR documents as invoices with embedded settlement data.
- Reversed RCs with status `A`, carrying reversal date and reason.
- Each document includes the `hash_code` and key version.
- Product codes map to BillingItem `code` (immutable for this reason).
- File checksum recorded in audit log.

---

### 20.20 Expenses

#### 20.20.1 Entity: `ExpenseCategory`

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `school_id` | UUID | FK schools |
| `name` | String(100) | |
| `description` | Text | |
| `is_active` | Boolean | |
| `created_at` | DateTime | |

#### 20.20.2 Entity: `Expense`

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `school_id` | UUID | FK schools |
| `category_id` | UUID | FK expense_categories |
| `amount` | Numeric(12,2) | |
| `expense_date` | Date | |
| `description` | Text | |
| `vendor` | String(200) | |
| `reference_number` | String(100) | External receipt/invoice number |
| `receipt_url` | String(500) | Uploaded scan |
| `payment_method` | String(30) | |
| `is_voided` | Boolean | |
| `void_reason` | Text | |
| `created_by` | UUID | FK users |
| `created_at`, `updated_at` | DateTime | |

#### 20.20.3 Business Rules

- Expenses are **never hard-deleted** (see Cross-Cutting Rules 22.2).
- Voided expenses are excluded from totals but retained permanently.
- Expenses do not generate fiscal documents (they are internal cost tracking).
- `school_admin` only for create/void.

#### 20.20.4 Use Cases

- **UC-EX1:** Admin creates an expense (amount, date, category, vendor, description, optional receipt upload).
- **UC-EX2:** Admin lists expenses filterable by category, date range, voided status.
- **UC-EX3:** Admin voids an expense (mandatory reason).
- **UC-EX4:** Admin uploads receipt scan for an expense.
- **UC-EX5:** Admin manages expense categories.

---

### 20.21 Finance Roles & Permissions

`school_admin` alone is too coarse for finance operations. The `finance_officer` role provides day-to-day operational access without destructive capabilities.

| Action | finance_officer | school_admin | platform_admin |
|--------|:---:|:---:|:---:|
| Record payments, issue RC/FR | Yes | Yes | Yes |
| Create invoices (single + bulk) | Yes | Yes | Yes |
| Manage cash sessions (open/close) | Yes | Yes | Yes |
| Generate/register payment references | Yes | Yes | Yes |
| View reports (dashboard, P&L, outstanding) | Yes | Yes | Yes |
| Cancel invoice / issue NC/ND | - | Yes | Yes |
| Reverse payments | - | Yes | Yes |
| Reopen cash sessions | - | Yes | Yes |
| Manage BillingItems, price tables | - | Yes | Yes |
| Manage contracts | - | Yes | Yes |
| Credit refunds / manual adjustments | - | Yes | Yes |
| Manage expenses | - | Yes | Yes |
| SAF-T export | - | Yes | Yes |
| Key management, provider config | - | Yes | Yes |
| Payment plans (create/modify) | - | Yes | Yes |
| View audit log | - | Yes | Yes |
| Parent: own invoices, statement, credit | (parent role) | | |

---

### 20.22 `DocumentEmissionService` - Architecture

All fiscal document creation flows through this service. Responsibilities:

```
DocumentEmissionService(db, school_id)
  |
  +-- emit_invoice(document_type, invoice_date, lines, guardian, ...)
  |     1. Compute line totals (apply discount, IVA, round)
  |     2. Sum to document totals
  |     3. Acquire series lock (SELECT FOR UPDATE on DocumentSeries)
  |     4. Validate monotonicity (dates >= previous)
  |     5. Assign next_number, increment series
  |     6. Format sign string, sign with RSA-SHA1
  |     7. Create Invoice + InvoiceLine records
  |     8. Set transmission_status (v1: not_required)
  |     9. Return signed Invoice
  |
  +-- emit_credit_note(invoice_id, reason, lines)
  |     1. Load and validate original invoice
  |     2. Validate credit amounts per line
  |     3. Update line credited_amounts
  |     4. Compute NC totals
  |     5. Sign in NC series
  |     6. Create CreditNote record
  |     7. If full void: mark invoice cancelled
  |     8. Else: recalculate invoice status
  |
  +-- emit_receipt(payment, allocations)
        1. Resolve customer info from guardian
        2. Sign in RC series
        3. Create Receipt record with settled_documents
```

---

### 20.23 `PaymentIntakeService` - Architecture

Single convergence point for all payment processing:

```
PaymentIntakeService(db, school_id)
  |
  +-- intake(guardian_id, amount, method, date, ...)
        1. Idempotency check (return existing if key matches)
        2. Validate cash session requirement (cash/check methods)
        3. Create Payment record
        4. Resolve target invoices:
           a. Reference-originated -> always target reference's invoice
           b. Explicit target_invoice_ids -> use those
           c. Neither -> oldest-first allocation for guardian
        5. Allocate: for each target invoice, apply min(balance, remaining)
        6. Create PaymentAllocation records
        7. Update invoice statuses (recalculate each)
        8. Surplus -> create CreditEntry (source=payment_surplus)
        9. Generate RC via DocumentEmissionService (unless FR or skip_receipt)
       10. Mark PaymentReference paid (if applicable)
       11. Return Payment
```

**Who calls intake:**
- Admin UI (manual payment recording)
- Mark-reference-paid endpoint (manual mode)
- Webhook endpoint (API mode, future)
- Credit application (with method=credit, skip_receipt=false)

---

### 20.24 `DocumentSeries` Entity

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | PK |
| `school_id` | UUID | FK schools |
| `document_type` | String(5) | FT, FR, NC, ND, RC |
| `year` | Integer | Series year |
| `next_number` | Integer | Next sequential number to assign |
| `last_hash` | Text | Hash of last document in chain |
| `last_invoice_date` | Date | For monotonicity check |
| `last_system_entry_date` | DateTime | For monotonicity check |
| `created_at` | DateTime | |

**Unique constraint:** (school_id, document_type, year).

Series are created lazily on first document emission for that type+year.

---

### 20.25 Concurrency & Performance

#### 20.25.1 Per-Series Locking

- `SELECT ... FOR UPDATE` on the `DocumentSeries` row during emission.
- This serializes all document creation within a series.
- Different series (e.g. FT and NC) can emit concurrently.
- Bulk generation holds the lock for the duration of the batch within one transaction.

#### 20.25.2 Performance Considerations

- Bulk invoice generation: batch within a single transaction per series to minimize lock contention.
- Account statement: indexed by (school_id, billing_guardian_id, invoice_date).
- Outstanding report: indexed by (school_id, status, document_type).
- SAF-T export: may be slow for large schools; consider background job with download link.
- Credit balance: sum query on (school_id, billing_guardian_id, is_reversed=false).

#### 20.25.3 Idempotency Requirements

| Guard | Scope | Mechanism |
|-------|-------|-----------|
| `idempotency_key` | Per school | Unique constraint, checked before create |
| `payment_reference_id` | Global | Unique on Payment table |
| (`provider`, `external_id`) | Global | Unique constraint on PaymentReference |
| Series number | Per series | Atomic increment under row lock |

---

### 20.26 Parent Finance Portal

Parents see a simplified view of their financial relationship with the school:

#### 20.26.1 Endpoints

- **View invoices:** All invoices for their linked children, with status and balance.
- **View statement:** Their guardian account statement (read-only).
- **View credit balance:** Current credit balance.
- **Submit payment proof:** Upload receipt/proof for admin verification (does NOT auto-create payment; admin reviews and records).
- **View payment references:** Active references for their invoices (entity, reference, amount, expiry).

#### 20.26.2 Business Rules

- Parent can only see data for their linked guardian account.
- Parent cannot create payments directly (only submit proof for review).
- Parent sees NIF prompt if their NIF is missing.
- Parent sees payment reference details to enable self-service ATM/bank payment.

---

### 20.27 Scheduled Jobs

| Job | Frequency | Action |
|-----|-----------|--------|
| Mark overdue invoices | Daily | Set `status=overdue` where due_date < today and status in (pending, partially_paid) |
| Expire payment references | Daily | Set `status=expired` where expires_at < now and status=active |
| Breach payment plans | Daily | Set plan `status=breached` where installment due_date < today and status=pending |
| Dunning check | Daily (optional) | Flag guardians eligible for next reminder level |

---

### 20.28 Error Handling & Edge Cases

| Scenario | Handling |
|----------|----------|
| Bulk generation with no active contracts | Return empty result with warning |
| Payment for guardian with no open invoices | Entire amount becomes CreditEntry |
| NC for more than available line balance | Reject with specific error per line |
| Reversal of payment with applied credit | Block; require credit reversal first |
| Cash payment without open session | Reject; require session to be opened first |
| Duplicate webhook (same external_id) | Return existing payment (idempotent) |
| Duplicate admin submission (same idempotency_key) | Return existing payment |
| Clock skew violates SystemEntryDate monotonicity | Reject emission; alert for ops investigation |
| FR where payment method = credit | Valid; FR can be settled by credit balance |
| ND referencing a cancelled/voided invoice | Reject; ND only references active FT |
| Guardian with multiple children, partial payment | Allocates oldest-first across all children's invoices |
| SAF-T export for empty period | Generate valid XML with empty document sections |
| Payment amount = 0 | Reject; minimum payment is 0.01 |
| Invoice with all lines at 0.00 | Technically valid but flagged as warning |

---

### 20.29 REST API Summary

All endpoints under `/api/v1/finance/`.

| Method | Path | Access | Description |
|--------|------|--------|-------------|
| GET | `/billing-items` | finance_officer+ | List billing items |
| POST | `/billing-items` | school_admin | Create billing item |
| PATCH | `/billing-items/{id}` | school_admin | Update billing item |
| GET | `/billing-items/{id}/prices` | finance_officer+ | Price history |
| POST | `/billing-items/prices` | school_admin | Set price for school year |
| GET | `/contracts` | finance_officer+ | List contracts |
| POST | `/contracts` | school_admin | Create contract |
| GET | `/contracts/{id}` | finance_officer+ | Get contract detail |
| PATCH | `/contracts/{id}` | school_admin | Update contract |
| DELETE | `/contracts/{id}` | school_admin | Terminate contract |
| GET | `/invoices` | finance_officer+ | List invoices (filterable) |
| POST | `/invoices` | finance_officer+ | Create single invoice |
| POST | `/invoices/bulk` | finance_officer+ | Bulk generate for month |
| GET | `/invoices/{id}` | finance_officer+ | Invoice detail with lines |
| POST | `/credit-notes` | school_admin | Issue NC (full or partial) |
| GET | `/credit-notes` | finance_officer+ | List credit notes |
| GET | `/credit-notes/{id}` | finance_officer+ | Credit note detail |
| GET | `/payments` | finance_officer+ | List payments |
| POST | `/payments` | finance_officer+ | Record payment (intake) |
| POST | `/payments/{id}/reverse` | school_admin | Reverse payment |
| GET | `/receipts` | finance_officer+ | List receipts |
| GET | `/payment-references` | finance_officer+ | List references |
| POST | `/payment-references` | finance_officer+ | Create/register reference |
| POST | `/payment-references/{id}/mark-paid` | finance_officer+ | Manual mark-paid (intake) |
| POST | `/payment-references/{id}/cancel` | finance_officer+ | Cancel reference |
| GET | `/credits/{guardian_id}` | finance_officer+ | Guardian credit balance + history |
| POST | `/credits/apply` | school_admin | Apply credit to invoice |
| GET | `/cash-sessions` | finance_officer+ | List sessions |
| POST | `/cash-sessions/open` | finance_officer+ | Open session |
| POST | `/cash-sessions/{id}/close` | finance_officer+ | Close session |
| GET | `/payment-plans` | finance_officer+ | List plans |
| POST | `/payment-plans` | school_admin | Create plan |
| POST | `/reminders` | finance_officer+ | Record reminder sent |
| GET | `/reminders` | finance_officer+ | Reminder history |
| GET | `/parent/invoices` | parent | Own invoices |
| GET | `/parent/statement` | parent | Own statement |
| POST | `/parent/submit-payment` | parent | Upload payment proof |
| POST | `/payment-proof` | finance_officer+ | Upload proof for payment |
| GET | `/dashboard` | finance_officer+ | KPIs |
| GET | `/summary` | finance_officer+ | Quick summary |
| GET | `/reports/pl` | finance_officer+ | P&L report |
| GET | `/reports/outstanding` | finance_officer+ | Outstanding invoices |
| GET | `/reports/delinquent` | finance_officer+ | Delinquent guardians |
| GET | `/reports/cash-flow` | finance_officer+ | Cash flow over months |
| GET | `/reports/statement/{guardian_id}` | finance_officer+ | Guardian statement |
| GET | `/reports/saft` | school_admin | SAF-T XML export |
| GET | `/series` | finance_officer+ | Document series list |
| GET | `/expense-categories` | school_admin | List categories |
| POST | `/expense-categories` | school_admin | Create category |
| PATCH | `/expense-categories/{id}` | school_admin | Update category |
| GET | `/expenses` | school_admin | List expenses |
| POST | `/expenses` | school_admin | Create expense |
| PATCH | `/expenses/{id}` | school_admin | Update expense |
| POST | `/expenses/{id}/void` | school_admin | Void expense |
| POST | `/expenses/{id}/receipt` | school_admin | Upload receipt |
| GET | `/audit-log` | school_admin | View audit entries |

---

### 20.30 Future Extensibility (Out of Scope for v1)

Reserved extension points that require no redesign:

1. **Multicaixa Express integration** - Plug into `PaymentReferenceProvider` abstraction.
2. **AGT real-time transmission** - Plug into `TransmissionProvider` (20.14).
3. **Multi-register cash sessions** - Add `register_id` to CashSession.
4. **Recurring billing scheduler** - Cron-triggered bulk generation with configurable day-of-month.
5. **Write-offs** - New document type or special NC with write-off reason.
6. **Scholarships/bursaries** - Modeled as contracts with 100% discount or as manual credit adjustments.
7. **Late fee automation** - Auto-generation of ND after configurable days overdue.
8. **Multi-currency** - Add currency field to documents; exchange rate at emission time.
9. **Email/SMS delivery of documents** - Delivery channel on document emission.
10. **Parent self-service payment** - Direct Multicaixa Express checkout flow.

---

*End of Finance Module SRS.*

## 21. Parent Portal

The parent portal is a simplified view of the full system, showing only data relevant to the parent's linked children.

**Navigation sections:**
1. **Dashboard** — Child cards with quick links
2. **Caderneta** — Today's and recent daily reports from teachers
3. **Finanças** — Invoice list with balances and Multicaixa references
4. **Saúde** — Health events and immunization records
5. **Documentos** — School shared documents
6. **Avisos** — Announcements
7. **Mensagens** — Direct messages with school staff
8. **Marcações** — Appointment requests
9. **Cardápio** — Weekly food menu
10. **Notificações** — All notifications

**Parent-specific business rules:**
- Parent sees only data for their linked children.
- Parent cannot modify any child data (read-only except appointments and authorizations).
- Parent can request an appointment with any employee.
- Parent can respond to trip authorization requests.
- Parent can add/remove pickup authorization persons for their children.

---

## 22. Cross-Cutting Rules

### 22.1 Data Isolation
- All queries filter by `school_id` derived from the authenticated user's token.
- `school_id` is never accepted as a client parameter in school-scoped endpoints.
- Platform admin endpoints operate across all schools.

### 22.2 Soft Deletes and Financial Immutability
- Children, employees, guardians, and users use soft delete (`is_active = false`).
- Soft-deleted records are excluded from all list queries by default.
- Hard deletes are permitted only for non-financial content: documents, photos, and authorized pickup persons.

**Financial records are immutable:**
- **Expenses may never be hard-deleted.** Hard-deleting an expense destroys the audit trail, retroactively alters historical P&L reports, and breaks cash flow continuity. An expense recorded in error must be *voided* — marked with a `is_voided = true` flag and a `void_reason`, and excluded from totals — but the record remains in the database permanently.
- Invoices, payments, receipts, and credit notes follow the same rule: they are never deleted, only transitioned to terminal statuses (`cancelled`, `void`, `reversed`).
- This ensures that any P&L or cash flow report for a past period will always produce the same result when re-run, regardless of corrections made later.

### 22.3 Pagination
- All list endpoints that may return large datasets support `limit` and `offset` (or `page`) query parameters.
- Default page size: 50.

### 22.4 Currency
- Currency is stored per school.
- All monetary values are stored as `NUMERIC(10, 2)`.
- The UI always formats amounts with the school's configured currency symbol.

### 22.5 Timestamps
- All records have `created_at` and `updated_at` stored as full UTC datetimes (`TIMESTAMP WITH TIME ZONE`).
- Business-logic date fields (invoice date, expense date, event date) are stored as `DATE` (no time component) since only the calendar date matters.
- Fields where the time of day matters use `TIMESTAMP` or `TIME`: `check_in_time`, `check_out_time`, `incident_time`, `health_event_time`.
- **AGT-specific rule:** The `SystemEntryDate` field used in the RSA-SHA1 signature string must be the `created_at` full timestamp formatted as `YYYY-MM-DDThh:mm:ss` (local Angola time, WAT = UTC+1). Using a DATE-only value here produces an invalid signature that will fail AGT certification. The `created_at` column on financial documents must therefore always be a full datetime, never truncated.

### 22.6 Notifications
- Any server-side event that requires user awareness (new caderneta, serious incident, overdue invoice, trip request) must create a `Notification` record for the relevant user(s).
- Notification delivery is in-app only (no push to device in v1).

---

## 23. Feature Completeness Matrix

| Feature | Backend | Flutter Screen | Tests | Status |
|---------|---------|---------------|-------|--------|
| Platform admin (schools CRUD) | ✅ | ✅ | ✅ | Done |
| Auth (login, refresh, change-pwd) | ✅ | ✅ | ✅ | Done |
| School profile + logo | ✅ | ✅ | ✅ | Done |
| School years | ✅ | ❓ | ✅ | UI unclear |
| Children CRUD | ✅ | ✅ | ✅ | Done |
| Guardians CRUD + link | ✅ | ✅ | ✅ | Done |
| Employees CRUD | ✅ | ✅ | ✅ | Done |
| Turmas | ✅ | ✅ | ❓ | Tests missing |
| Schedules | ✅ | ✅ | ❓ | Tests missing |
| Enrollments | ✅ | ✅ | ❓ | Tests missing |
| Attendance check-in/out | ✅ | ✅ | ❓ | Not wired up fully |
| Employee absences | ✅ | ❓ | ❓ | UI missing |
| Caderneta | ✅ | ✅ | ❓ | Tests missing |
| Food items + menus | ✅ | ✅ | ❓ | Tests missing |
| Meal orders | ✅ | ✅ | ❓ | Tests missing |
| Health events | ✅ | ✅ | ✅ | Done |
| Immunizations | ✅ | ✅ | ✅ | Done |
| Incidents | ✅ | ✅ | ✅ | Done |
| Evaluations | ✅ | ✅ | ✅ | Done |
| Announcements | ✅ | ✅ | ✅ | Done |
| Messages (direct) | ✅ | ✅ | ❓ | Tests missing |
| Events | ✅ | ✅ | ✅ | Done |
| Notifications | ✅ | ✅ | ✅ | Done |
| Pickup authorizations | ✅ | ✅ | ❓ | Tests missing |
| Trip authorizations | ✅ | ✅ | ❓ | Tests missing |
| Documents library | ✅ | ✅ | ❓ | Tests missing |
| Photos | ✅ | ✅ | ❓ | Tests missing |
| Appointments | ✅ | ✅ | ✅ | Done |
| Service catalog (BillingItem) | ❌ | ❌ | ❌ | Not built |
| Expenses (void instead of delete) | ⚠️ | ✅ | ❓ | Backend allows delete — must fix |
| Invoices (guardian-billed + line items) | ⚠️ | ✅ | ❓ | Currently child-billed, no line items — must fix |
| Payments + auto-allocation | ✅ | ✅ | ❓ | Explicit targeting not yet supported |
| Contracts (linked to BillingItem) | ⚠️ | ✅ | ❓ | Currently free-text — must fix |
| Receipts / Credit notes | ✅ | ✅ | ❓ | Tests missing |
| Finance reports (P&L, cash flow…) | ✅ | ❓ | ❓ | UI + tests missing |
| Finance dashboard | ✅ | ✅ | ❓ | Tests missing |
| SAF-T export (with MasterFiles) | ⚠️ | ✅ | ❓ | Missing Customer + Product MasterFiles |
| Parent portal | ✅ | ✅ | ❓ | Not fully wired |
