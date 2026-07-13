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

## 20. Finance

The finance module must comply with Angola's AGT (Autoridade Geral Tributária) requirements for electronic invoicing.

### 20.1 Configuration

**Document series:** Each document type (FT = Factura, NC = Nota de Crédito, RC = Recibo) requires a series per year. The series is created on first use.

**Digital signature chain (AGT requirement):**
AGT certification requires an **RSA-SHA1 asymmetric digital signature**, not a plain SHA-1 hash. The two are fundamentally different:

- A simple SHA-1 hash can be reproduced by anyone — it provides no tamper evidence.
- An RSA-SHA1 signature can only be produced by the holder of the private key, and can be verified by any holder of the public key. This is what AGT audits.

**Implementation requirements:**
1. Generate a 1024-bit RSA key pair (minimum; 2048-bit preferred).
2. Register the public key with AGT during software certification.
3. Store the private key server-side, never exposed to clients.
4. For each document (FT, NC, RC), sign the following string using the private key:
   ```
   {InvoiceDate}\n{SystemEntryDate}\n{DocumentNumber}\n{GrossTotal}\n{PreviousHash}
   ```
   where:
   - `InvoiceDate` = `YYYY-MM-DD` (the document date)
   - `SystemEntryDate` = `YYYY-MM-DDThh:mm:ss` (full ISO 8601 timestamp of record creation — **always a full datetime, never a DATE-only value**)
   - `DocumentNumber` = full document number, e.g. `FT 2025/1`
   - `GrossTotal` = total amount as a decimal string with 2 decimal places, e.g. `12500.00`
   - `PreviousHash` = the `hash_code` of the previous document in the series; `"0"` for the first document
5. The resulting signature (Base64-encoded) is stored in `hash_code`.
6. The `previous_hash` of each document stores the `hash_code` of its predecessor, forming a verifiable chain.

**Key management:**
- The private key is stored encrypted on the server (environment variable or secrets manager), never in the database.
- If the key is compromised or lost, the school must re-certify with AGT and restart their hash chain — this is a critical operational risk.
- Key rotation requires AGT re-certification.

### 20.2 Service Catalog (BillingItem)

AGT SAF-T validation requires every invoice line item to reference a product or service code defined in the system's `MasterFiles/Product` section. Free-text descriptions alone are not sufficient — each line must map to a catalogued item with a stable code, description, and fiscal attributes.

**Use cases:**
- UC-FSC1: Admin creates a billing item (e.g. monthly tuition for a given level)
- UC-FSC2: Admin lists all billing items
- UC-FSC3: Admin updates a billing item (name, default price, IVA attributes)
- UC-FSC4: Admin deactivates a billing item (cannot delete if referenced by invoices)

**Data per BillingItem:**
- `code` — unique within the school, short and stable (e.g. `MENS-BERC`, `MENS-CRECHE`, `MENS-JARDIN`, `EXTRAS`, `MATRICULA`)
- `name` — human-readable name (e.g. "Mensalidade Berçário", "Matrícula")
- `description` — optional extended description
- `unit_price` — default price (can be overridden per invoice line)
- `iva_rate` — default IVA rate (0.00 for education services)
- `iva_exemption_reason` — default exemption code (e.g. `M10`)
- `is_active` — soft delete flag

**Seeded defaults on school creation:**

| Code | Name | IVA | Exemption |
|------|------|-----|-----------|
| `MENS-BERC` | Mensalidade Berçário | 0% | M10 |
| `MENS-CRECHE` | Mensalidade Creche | 0% | M10 |
| `MENS-JARDIN` | Mensalidade Jardim de Infância | 0% | M10 |
| `MATRICULA` | Matrícula / Inscrição | 0% | M10 |
| `EXTRAS` | Serviços Extra-Curriculares | 0% | M10 |
| `TRANSP` | Transporte Escolar | 0% | M10 |
| `ALIM` | Alimentação | 0% | M10 |

**SAF-T MasterFiles output:** When exporting SAF-T, the system compiles every `BillingItem` referenced by documents in the export period into the `<MasterFiles><Product>` section, using `code` as `<ProductCode>`, `name` as `<ProductDescription>`, and the IVA attributes for the product group.

**Business rules:**
- A `BillingItem` can be deactivated but never deleted if it is referenced by any invoice line, contract, or SAF-T export.
- The `code` is immutable once created — it is the stable identifier in SAF-T exports across multiple periods.
- Schools can create custom items beyond the seeded defaults.

---

### 20.3 Expense Categories

**Use cases:**
- UC-FEC1: Admin creates expense categories (e.g. Salários, Alimentação, Manutenção)
- UC-FEC2: Admin lists categories
- UC-FEC3: Admin updates a category

**Business rules:**
- Default categories on school creation: `salary`, `utilities`, `food`, `supplies`, `maintenance`, `other`.
- Categories are school-specific.

### 20.4 Expenses

**Use cases:**
- UC-FE1: Admin records an expense
- UC-FE2: Admin lists expenses (filterable by category, date range, school year)
- UC-FE3: Admin views expense detail
- UC-FE4: Admin updates an expense (only while status is `active`)
- UC-FE5: Admin voids an expense recorded in error (sets `is_voided = true`, records `void_reason`)
- UC-FE6: Admin uploads a receipt for an expense

**Data per expense:** description, amount, date, category, payment method, reference, receipt_url, notes, registered_by, school_year

**Payment methods:** `cash`, `transfer`, `multicaixa`, `check`, `other`

**Business rules:**
- Only `school_admin` can manage expenses.
- Receipts are optional attachments (image or PDF, max 5 MB).

### 20.5 Invoices

**Use cases:**
- UC-FI1: Admin creates a single invoice for a guardian (specifying which child the service is for)
- UC-FI2: Admin bulk-creates invoices for all active enrollments in a reference month
- UC-FI3: Admin views invoice list (filterable by guardian, child, status, month, year)
- UC-FI4: Admin views invoice detail with balance (total − payments)
- UC-FI5: Admin cancels an unpaid invoice
- UC-FI6: Admin voids a paid invoice (creates credit note)
- UC-FI7: Admin generates Multicaixa payment reference for an invoice
- UC-FI8: Parent views their own invoices with payment status

**Invoice statuses:** `pending`, `partially_paid`, `paid`, `cancelled`, `overdue`

**Invoicing entity — legal requirement:**

Under AGT regulations, a tax document (Factura) must be issued to a legally responsible person or entity — not a minor. The SAF-T `MasterFiles/Customer` section requires each customer to have a `Name`, `BillingAddress`, and `TaxRegistrationNumber` (NIF). A child has none of these.

**The Invoice belongs to a Guardian (or corporate sponsor), not the Child.**

- `billing_guardian_id` (FK → Guardian) — the legally responsible party receiving the invoice. This is the primary billing contact. The guardian's name, NIF, and address populate the SAF-T `Customer` record.
- `child_id` — retained as **metadata only**, used to populate the line item description (e.g. "Mensalidade Outubro 2025 — Ana Silva") and for filtering invoices by child in the UI. It carries no fiscal weight.
- Both fields are required on every invoice.

**Data per invoice (header):**
- `billing_guardian_id` — FK to Guardian (the invoice recipient, legally)
- `child_id` — FK to Child (metadata for line item description)
- `issued_by` — employee who created the invoice
- `school_year_id`
- `invoice_date` — `DATE`
- `reference_month` — e.g. `2025-10` (YYYY-MM)
- `due_date` — `DATE`
- `status` — `pending` | `partially_paid` | `paid` | `cancelled` | `overdue`
- `document_type` — `FT`
- `series_year`, `series_number`, `full_document_number` — e.g. `FT 2025/42`
- `hash_code`, `previous_hash` — RSA-SHA1 signature chain (see 20.1)
- `cancellation_reason`, `cancelled_at` — set when status becomes `cancelled`
- `multicaixa_entity`, `multicaixa_ref` — optional payment reference
- `notes`

**Data per invoice line item (`InvoiceLine`):**
- `invoice_id`
- `billing_item_id` — FK to BillingItem (see 20.2). This drives the SAF-T `<ProductCode>`.
- `description` — human-readable line description, auto-populated from BillingItem name + child name (e.g. "Mensalidade Outubro 2025 — Ana Silva"), editable by admin
- `quantity` — typically `1`
- `unit_price` — amount for this line (copied from BillingItem default, editable)
- `iva_rate` — copied from BillingItem, editable
- `iva_exemption_reason` — required when `iva_rate = 0%`; copied from BillingItem
- `iva_amount` — computed: `unit_price × quantity × iva_rate`
- `line_total` — computed: `unit_price × quantity + iva_amount`

**Invoice total** = sum of all `line_total` values across all lines.

**Workflow — Monthly billing (bulk):**
1. Admin selects reference month and triggers `POST /finance/invoices/bulk`.
2. System iterates all active enrollments for the school year.
3. For each enrollment: identifies the child's primary-contact guardian (`is_primary_contact = true`). If none exists, that child is **skipped** and reported in a warning list — bulk generation cannot proceed without a billing guardian.
4. System fetches active contracts for the child. Each contract maps to a `BillingItem` and contributes one `InvoiceLine`.
5. If no contract exists, the system uses the school's default tuition item for the child's turma level (e.g. `MENS-BERC` for Berçário).
6. Invoice header is created under the guardian. Lines are created per service.
7. Hash chain signature is computed and stored.
8. Admin reviews the generated invoices and any warnings (children skipped due to missing guardian).
9. Admin sends payment references to parents.

**Workflow — Voiding a paid invoice:**
1. Admin requests void with a reason.
2. System creates a credit note (NC) mirroring all lines with negative amounts.
3. Invoice status changes to `void`. The original document remains in the hash chain.
4. Credit note is linked to the original invoice and signed into the NC hash chain.

**Business rules:**
- Invoice numbers are sequential per series per year, never reused.
- Once an invoice is `paid`, it can only be voided (not cancelled).
- `cancelled` status (AGT status `A` — *Anulado*) is for invoices that were never paid.
- **A cancelled invoice is never deleted.** It stays in the hash chain and is exported to SAF-T with status `A`. Gaps in the chain break AGT validation.
- Bulk creation skips children who already have an invoice for the reference month (idempotent).
- IVA on Angola education services is 0% (exempt under CIVA). Every line must carry `iva_rate = 0.00` and a valid `iva_exemption_reason` — both fields are required, not optional.

### 20.6 Payments

**Use cases:**
- UC-FP1: Admin records a payment received from a guardian
- UC-FP2a: System auto-allocates payment to oldest outstanding invoices (default behaviour)
- UC-FP2b: Admin or parent explicitly targets specific invoices when recording payment
- UC-FP3: Admin views payment list (by guardian, child, date range)
- UC-FP4: Admin views payment detail with the invoices it settled
- UC-FP5: Admin reverses a payment (voids payment and reverses all allocations)

**Data per payment:** `billing_guardian_id`, `child_id` (for filtering), date, amount, payment method, receipt number, notes, received by, `target_invoice_ids` (optional, at creation time only)

**Payment methods:** `cash`, `transfer`, `multicaixa`, `check`, `other`

**Allocation modes:**

**Default — oldest-first auto-allocation:**
The system allocates the payment amount to the guardian's outstanding invoices sorted by `invoice_date` ascending (oldest unpaid first). Any surplus after settling one invoice rolls over to the next.

**Explicit targeting (optional):**
The `POST /finance/payments` payload accepts an optional `invoice_ids: [uuid]` array. When provided:
1. The system allocates funds **only** to the listed invoices, in the order they are listed.
2. If the payment amount is less than the total of the targeted invoices, the first listed invoice is partially settled, then the next, and so on.
3. If the payment amount exceeds the total of the targeted invoices, the surplus is recorded as a **credit balance** on the guardian's account (not auto-applied to other invoices).
4. Non-targeted invoices are untouched, regardless of their age.

This mode exists to handle common school scenarios: a parent who disputes one invoice and explicitly pays a different one; Multicaixa references that correspond to specific invoices; batch payments from a sponsor covering a defined set of documents.

**Workflow — Recording a payment (admin):**
1. Admin opens payment form, selects guardian and enters amount, method, and date.
2. Admin optionally selects specific invoices to target. If none selected, oldest-first applies.
3. System runs allocation (default or targeted) and updates invoice statuses.
4. A receipt document (RC) is generated and signed into the RC hash chain.

**Workflow — Reversing a payment:**
1. Admin selects payment and requests reversal with reason.
2. System marks payment as `reversed` (not deleted — financial immutability).
3. All `PaymentInvoice` allocation records for this payment are reversed: invoices revert to their pre-payment status (`pending` or `partially_paid`).
4. The RC document for this payment is annotated as reversed; a compensating entry is recorded.

**Business rules:**
- Payment amount must be > 0.
- Payments are issued under a `billing_guardian_id`. The `child_id` field is optional metadata used for UI filtering; the legal relationship is guardian → invoice.
- A payment can settle multiple invoices in one transaction (both modes).
- A reversed payment is never deleted — it is permanently marked `reversed` with a reason and timestamp.
- `invoice_ids` must all belong to the same school and the same guardian; mixing guardians in one payment is not permitted.

### 20.7 Contracts

**Use cases:**
- UC-FC1: Admin creates a recurring service contract for a child
- UC-FC2: Admin lists active contracts
- UC-FC3: Admin updates a contract (unit price, dates, billing cycle)
- UC-FC4: Admin deactivates a contract
- UC-FC5: Admin manually generates an invoice from a contract
- UC-FC6: System auto-generates invoices for all active contracts on schedule

**Data per contract:** `child_id`, `billing_item_id` (FK → BillingItem — defines what service is being billed), `unit_price` (override of BillingItem default, nullable — if null, uses BillingItem's `unit_price`), billing cycle (`monthly`), `day_of_month` for billing, `start_date`, `end_date`, `auto_invoice` flag, `last_invoiced_month`

When a contract is used to generate an invoice line:
- `InvoiceLine.billing_item_id` = the contract's `billing_item_id`
- `InvoiceLine.unit_price` = the contract's `unit_price` (or BillingItem default)
- `InvoiceLine.iva_rate`, `iva_exemption_reason` = copied from the BillingItem

**Business rules:**
- A child can have multiple contracts (e.g. tuition + transport + extra-curricular), each linked to a different `BillingItem`.
- Bulk auto-generate checks `last_invoiced_month` to avoid generating duplicate invoices in the same month.
- Contracts with `auto_invoice = false` must be triggered manually.
- Deactivating a contract (`is_active = false`) stops future auto-generation but does not affect existing invoices.

### 20.8 Receipts and Credit Notes

**Use cases:**
- UC-FR1: Admin views all receipts
- UC-FR2: System auto-generates receipt when payment is recorded
- UC-FR3: Admin views all credit notes
- UC-FR4: System auto-generates credit note when invoice is voided

**Business rules:**
- Receipts and credit notes are read-only once generated.
- Each has a sequential document number in their series (RC and NC respectively).
- The RSA-SHA1 hash chain applies to both receipts (RC) and credit notes (NC), using the same signing algorithm defined in 20.1.

**Receipt line items (AGT requirement):**
A receipt (RC) must not be a lump-sum document. The RC must contain explicit line items, one per settled invoice, each referencing:
- `full_document_number` of the invoice being settled (e.g. `FT 2025/42`)
- `amount_applied` — the amount from this payment allocated to that invoice

This is mandatory for the SAF-T `<SourceDocuments><Payments>` section to pass AGT validation. A receipt that references no invoice documents will be rejected. The `PaymentInvoice` allocation records (linking `payment_id` → `invoice_id` → `amount_applied`) are the source of truth for these line items — the RC generation reads directly from them.

### 20.9 Finance Reports

**Use cases:**
- UC-FRP1: Admin views Profit & Loss (by month or full year)
- UC-FRP2: Admin views Outstanding Invoices with aging buckets
- UC-FRP3: Admin views Cash Flow (monthly income vs. expenses)
- UC-FRP4: Admin views Revenue by Level (Berçário / Creche / Jardim)
- UC-FRP5: Admin views Delinquency Report (overdue > 30 days, with guardian contacts)
- UC-FRP6: Admin exports SAF-T XML for submission to AGT

**P&L components:**
- Revenue: sum of paid invoices in period
- Expenses: sum of expenses in period
- Net: revenue − expenses

**Aging buckets:** 0–30 days, 31–60 days, 61–90 days, 90+ days

**SAF-T export:** Must include, for the selected period:
- `MasterFiles/Customer` — one entry per unique `billing_guardian_id` referenced by documents in the period (name, NIF, billing address)
- `MasterFiles/Product` — one entry per unique `BillingItem` referenced by invoice lines in the period (code, name, IVA group)
- `SourceDocuments/SalesInvoices` — all FT documents (including cancelled, status `A`)
- `SourceDocuments/Payments` — all RC documents (including reversed)
- `SourceDocuments/SalesInvoices` (credit notes) — all NC documents

### 20.10 Finance Dashboard

**KPIs shown:**
- Current month revenue (paid invoices)
- Current month expenses
- Net margin for current month
- Total outstanding balance (all unpaid invoices)
- Count of overdue invoices
- Count of pending invoices
- Recent payment activity (last 5 payments)

---

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
