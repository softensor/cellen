-- =============================================================================
-- Cellen Database Schema
-- Multi-tenant SaaS childcare management system
--
-- Multi-tenancy design:
--   - `schools` is the root tenant entity.
--   - Every table EXCEPT `schools` and `platform_users` carries
--     school_id UUID NOT NULL REFERENCES schools(id).
--   - Application layer ALWAYS filters queries by school_id extracted from JWT.
--   - Row-level isolation is enforced via application logic; no cross-tenant
--     data is returned regardless of primary key lookups.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- PLATFORM LEVEL
-- =============================================================================

CREATE TABLE schools (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    VARCHAR(255) NOT NULL,
    slug                    VARCHAR(100) UNIQUE NOT NULL,
    address                 VARCHAR(500),
    city                    VARCHAR(100),
    country                 VARCHAR(10),
    phone                   VARCHAR(50),
    email                   VARCHAR(255),
    logo_url                VARCHAR(500),
    is_active               BOOLEAN DEFAULT TRUE,
    subscription_started_at TIMESTAMPTZ,
    subscription_notes      TEXT,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE schools IS 'Root tenant entity. Every other table (except platform_users) references this.';

CREATE TABLE platform_users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active     BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE platform_users IS 'Superusers who manage the platform. Not tied to any school.';

-- =============================================================================
-- EMPLOYEES (must come before users)
-- =============================================================================

CREATE TABLE employees (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id        UUID NOT NULL REFERENCES schools(id),
    first_name       VARCHAR(100) NOT NULL,
    middle_name      VARCHAR(100),
    last_name        VARCHAR(100) NOT NULL,
    birth_date       DATE,
    place_of_birth   VARCHAR(255),
    sex              VARCHAR(1),
    civil_state      VARCHAR(50),
    nationality      VARCHAR(100),
    naturality       VARCHAR(100),
    height           NUMERIC(5,2),
    profession       VARCHAR(255),
    qualifications   VARCHAR(255),
    id_card_number   VARCHAR(100),
    photo_url        VARCHAR(500),
    street           VARCHAR(255),
    house_number     VARCHAR(50),
    building_number  VARCHAR(50),
    apt_number       VARCHAR(50),
    city             VARCHAR(100),
    municipio        VARCHAR(100),
    bairro           VARCHAR(100),
    mobile_first     VARCHAR(50),
    mobile_second    VARCHAR(50),
    email            VARCHAR(255),
    employee_type    VARCHAR(50) NOT NULL,
    position         VARCHAR(255),
    title_academic   VARCHAR(255),
    social_security  VARCHAR(100),
    contract_type    VARCHAR(50),
    hire_date        DATE,
    salary           NUMERIC(10,2),
    status           VARCHAR(20) DEFAULT 'active',
    privilege        VARCHAR(255),
    created_at       TIMESTAMPTZ DEFAULT NOW(),
    updated_at       TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (school_id, id_card_number)
);

CREATE INDEX ix_employees_school_id ON employees(school_id);

-- =============================================================================
-- GUARDIANS
-- =============================================================================

CREATE TABLE guardians (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id        UUID NOT NULL REFERENCES schools(id),
    first_name       VARCHAR(100) NOT NULL,
    middle_name      VARCHAR(100),
    last_name        VARCHAR(100) NOT NULL,
    birth_date       DATE,
    place_of_birth   VARCHAR(255),
    sex              VARCHAR(1),
    civil_state      VARCHAR(50),
    nationality      VARCHAR(100),
    naturality       VARCHAR(100),
    profession       VARCHAR(255),
    qualifications   VARCHAR(255),
    id_card_number   VARCHAR(100),
    photo_url        VARCHAR(500),
    street           VARCHAR(255),
    house_number     VARCHAR(50),
    building_number  VARCHAR(50),
    apt_number       VARCHAR(50),
    city             VARCHAR(100),
    municipio        VARCHAR(100),
    bairro           VARCHAR(100),
    mobile_first     VARCHAR(50),
    mobile_second    VARCHAR(50),
    email            VARCHAR(255),
    created_at       TIMESTAMPTZ DEFAULT NOW(),
    updated_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ix_guardians_school_id ON guardians(school_id);

-- =============================================================================
-- SCHOOL USERS
-- =============================================================================

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id     UUID NOT NULL REFERENCES schools(id),
    username      VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(50) NOT NULL,
    is_active     BOOLEAN DEFAULT TRUE,
    employee_id   UUID REFERENCES employees(id) ON DELETE SET NULL,
    guardian_id   UUID REFERENCES guardians(id) ON DELETE SET NULL,
    last_login    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    updated_at    TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (school_id, username)
);

CREATE INDEX ix_users_school_id ON users(school_id);

-- =============================================================================
-- CHILDREN
-- =============================================================================

CREATE TABLE children (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id               UUID NOT NULL REFERENCES schools(id),
    cedula                  VARCHAR(100) NOT NULL,
    first_name              VARCHAR(100) NOT NULL,
    middle_name             VARCHAR(100),
    last_name               VARCHAR(100) NOT NULL,
    birth_date              DATE,
    place_of_birth          VARCHAR(255),
    sex                     VARCHAR(1),
    nationality             VARCHAR(100),
    naturality              VARCHAR(100),
    height                  NUMERIC(5,2),
    special_needs           VARCHAR(500),
    medical_prescription    VARCHAR(500),
    photo_url               VARCHAR(500),
    is_active               BOOLEAN DEFAULT TRUE,
    street                  VARCHAR(255),
    house_number            VARCHAR(50),
    building_number         VARCHAR(50),
    apt_number              VARCHAR(50),
    city                    VARCHAR(100),
    municipio               VARCHAR(100),
    bairro                  VARCHAR(100),
    emergency_contact_name  VARCHAR(255),
    emergency_contact_phone VARCHAR(50),
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (school_id, cedula)
);

CREATE INDEX ix_children_school_id ON children(school_id);

CREATE TABLE child_guardians (
    id                  SERIAL PRIMARY KEY,
    school_id           UUID NOT NULL REFERENCES schools(id),
    child_id            UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    guardian_id         UUID NOT NULL REFERENCES guardians(id) ON DELETE RESTRICT,
    relationship        VARCHAR(50) NOT NULL,
    is_primary_contact  BOOLEAN DEFAULT FALSE,
    UNIQUE (child_id, guardian_id)
);

CREATE INDEX ix_child_guardians_school_id ON child_guardians(school_id);

-- =============================================================================
-- ACADEMIC
-- =============================================================================

CREATE TABLE school_years (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id   UUID NOT NULL REFERENCES schools(id),
    year_label  VARCHAR(20) NOT NULL,
    start_date  DATE NOT NULL,
    end_date    DATE NOT NULL,
    is_active   BOOLEAN DEFAULT FALSE,
    UNIQUE (school_id, year_label)
);

CREATE INDEX ix_school_years_school_id ON school_years(school_id);

CREATE TABLE turmas (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id     UUID NOT NULL REFERENCES schools(id),
    name          VARCHAR(100) NOT NULL,
    level         VARCHAR(100) NOT NULL,
    room          VARCHAR(100),
    max_capacity  INTEGER DEFAULT 0,
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ix_turmas_school_id ON turmas(school_id);

CREATE TABLE activities (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id   UUID NOT NULL REFERENCES schools(id),
    name        VARCHAR(255) NOT NULL,
    description VARCHAR(500),
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ix_activities_school_id ON activities(school_id);

CREATE TABLE schedules (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id      UUID NOT NULL REFERENCES schools(id),
    turma_id       UUID NOT NULL REFERENCES turmas(id) ON DELETE RESTRICT,
    school_year_id UUID NOT NULL REFERENCES school_years(id) ON DELETE RESTRICT,
    created_at     TIMESTAMPTZ DEFAULT NOW(),
    updated_at     TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (school_id, turma_id, school_year_id)
);

CREATE INDEX ix_schedules_school_id ON schedules(school_id);

CREATE TABLE schedule_teachers (
    schedule_id  UUID NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
    employee_id  UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
    school_id    UUID NOT NULL REFERENCES schools(id),
    PRIMARY KEY (schedule_id, employee_id)
);

CREATE INDEX ix_schedule_teachers_school_id ON schedule_teachers(school_id);

CREATE TABLE schedule_slots (
    id           SERIAL PRIMARY KEY,
    school_id    UUID NOT NULL REFERENCES schools(id),
    schedule_id  UUID NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
    day_of_week  INTEGER NOT NULL,
    slot_time    TIME NOT NULL,
    activity_id  UUID NOT NULL REFERENCES activities(id) ON DELETE RESTRICT,
    UNIQUE (schedule_id, day_of_week, slot_time)
);

CREATE INDEX ix_schedule_slots_school_id ON schedule_slots(school_id);

CREATE TABLE enrollments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id       UUID NOT NULL REFERENCES schools(id),
    child_id        UUID NOT NULL REFERENCES children(id) ON DELETE RESTRICT,
    schedule_id     UUID NOT NULL REFERENCES schedules(id) ON DELETE RESTRICT,
    school_year_id  UUID NOT NULL REFERENCES school_years(id) ON DELETE RESTRICT,
    enrollment_date DATE DEFAULT CURRENT_DATE,
    status          VARCHAR(20) DEFAULT 'active',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (school_id, child_id, school_year_id)
);

CREATE INDEX ix_enrollments_school_id ON enrollments(school_id);

-- =============================================================================
-- CADERNETA
-- =============================================================================

CREATE TABLE cadernetas (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id                   UUID NOT NULL REFERENCES schools(id),
    child_id                    UUID NOT NULL REFERENCES children(id) ON DELETE RESTRICT,
    teacher_id                  UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
    report_date                 DATE NOT NULL DEFAULT CURRENT_DATE,
    breakfast_rating            VARCHAR(50),
    lunch_rating                VARCHAR(50),
    snack_rating                VARCHAR(50),
    physiological_needs         VARCHAR(50),
    had_nap                     BOOLEAN,
    sensorial_motor_development VARCHAR(255),
    intellectual_development    VARCHAR(255),
    social_development          VARCHAR(255),
    affective_development       VARCHAR(255),
    general_observations        TEXT,
    created_at                  TIMESTAMPTZ DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (school_id, child_id, report_date)
);

CREATE INDEX ix_cadernetas_school_id   ON cadernetas(school_id);
CREATE INDEX ix_cadernetas_child_id    ON cadernetas(child_id);
CREATE INDEX ix_cadernetas_report_date ON cadernetas(report_date);

-- =============================================================================
-- FOOD
-- =============================================================================

CREATE TABLE foods (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id  UUID NOT NULL REFERENCES schools(id),
    name       VARCHAR(255) NOT NULL,
    details    VARCHAR(500),
    type       VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ix_foods_school_id ON foods(school_id);

CREATE TABLE food_menus (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id  UUID NOT NULL REFERENCES schools(id),
    level      VARCHAR(100) NOT NULL,
    start_date DATE NOT NULL,
    end_date   DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ix_food_menus_school_id ON food_menus(school_id);

CREATE TABLE food_menu_items (
    id             SERIAL PRIMARY KEY,
    school_id      UUID NOT NULL REFERENCES schools(id),
    food_menu_id   UUID NOT NULL REFERENCES food_menus(id) ON DELETE CASCADE,
    day_of_week    INTEGER NOT NULL,
    meal_type      VARCHAR(50) NOT NULL,
    meal_component VARCHAR(50),
    food_id        UUID NOT NULL REFERENCES foods(id) ON DELETE RESTRICT,
    UNIQUE (food_menu_id, day_of_week, meal_type, meal_component)
);

CREATE INDEX ix_food_menu_items_school_id ON food_menu_items(school_id);

-- =============================================================================
-- ABSENCES
-- =============================================================================

CREATE TABLE absences (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id      UUID NOT NULL REFERENCES schools(id),
    employee_id    UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
    responsible_id UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
    school_year_id UUID REFERENCES school_years(id) ON DELETE SET NULL,
    absence_date   DATE NOT NULL,
    justified      BOOLEAN DEFAULT FALSE,
    justification  TEXT,
    created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ix_absences_school_id   ON absences(school_id);
CREATE INDEX ix_absences_employee_id ON absences(employee_id);

-- =============================================================================
-- IMMUNIZATIONS
-- =============================================================================

CREATE TABLE immunizations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id       UUID NOT NULL REFERENCES schools(id),
    child_id        UUID NOT NULL REFERENCES children(id) ON DELETE RESTRICT,
    vaccine_name    VARCHAR(255) NOT NULL,
    administered_at DATE,
    due_date        DATE,
    administered_by VARCHAR(255),
    dose_number     INTEGER,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ix_immunizations_school_id ON immunizations(school_id);
CREATE INDEX ix_immunizations_child_id  ON immunizations(child_id);

-- =============================================================================
-- FINANCE
-- =============================================================================

CREATE TABLE expense_categories (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id   UUID NOT NULL REFERENCES schools(id),
    name        VARCHAR(255) NOT NULL,
    description VARCHAR(500),
    UNIQUE (school_id, name)
);

CREATE INDEX ix_expense_categories_school_id ON expense_categories(school_id);

COMMENT ON TABLE expense_categories IS
  'Default categories seeded on school creation: Salarios, Rendas, Servicos de Utilidade, Alimentacao, Material Escolar, Manutencao, Seguros, Outros';

CREATE TABLE expenses (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id      UUID NOT NULL REFERENCES schools(id),
    category_id    UUID NOT NULL REFERENCES expense_categories(id) ON DELETE RESTRICT,
    registered_by  UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
    school_year_id UUID REFERENCES school_years(id) ON DELETE SET NULL,
    description    VARCHAR(500) NOT NULL,
    amount         NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    expense_date   DATE NOT NULL,
    payment_method VARCHAR(50),
    reference      VARCHAR(255),
    receipt_url    VARCHAR(500),
    notes          TEXT,
    created_at     TIMESTAMPTZ DEFAULT NOW(),
    updated_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ix_expenses_school_id    ON expenses(school_id);
CREATE INDEX ix_expenses_expense_date ON expenses(expense_date);

CREATE TABLE invoices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id       UUID NOT NULL REFERENCES schools(id),
    child_id        UUID NOT NULL REFERENCES children(id) ON DELETE RESTRICT,
    issued_by       UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
    school_year_id  UUID REFERENCES school_years(id) ON DELETE SET NULL,
    invoice_date    DATE DEFAULT CURRENT_DATE,
    reference_month DATE NOT NULL,
    description     VARCHAR(500),
    tuition_amount  NUMERIC(10,2) DEFAULT 0,
    other_fees      NUMERIC(10,2) DEFAULT 0,
    total_amount    NUMERIC(10,2) DEFAULT 0,
    status          VARCHAR(20) DEFAULT 'pending',
    due_date        DATE,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ix_invoices_school_id ON invoices(school_id);
CREATE INDEX ix_invoices_child_id  ON invoices(child_id);

CREATE TABLE payments (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id      UUID NOT NULL REFERENCES schools(id),
    child_id       UUID NOT NULL REFERENCES children(id) ON DELETE RESTRICT,
    received_by    UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
    payment_date   DATE DEFAULT CURRENT_DATE,
    receipt_number VARCHAR(100),
    amount         NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    payment_method VARCHAR(50),
    notes          TEXT,
    created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX ix_payments_school_id    ON payments(school_id);
CREATE INDEX ix_payments_child_id     ON payments(child_id);
CREATE INDEX ix_payments_payment_date ON payments(payment_date);

CREATE TABLE payment_invoices (
    payment_id     UUID NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
    invoice_id     UUID NOT NULL REFERENCES invoices(id) ON DELETE RESTRICT,
    school_id      UUID NOT NULL REFERENCES schools(id),
    amount_applied NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (payment_id, invoice_id)
);

CREATE INDEX ix_payment_invoices_school_id ON payment_invoices(school_id);

COMMENT ON TABLE payment_invoices IS
  'Links payments to the invoices they settle. amount_applied supports partial payments.
   Service layer recalculates invoice.status after every insert/delete here.';

-- =============================================================================
-- END OF SCHEMA
-- =============================================================================
