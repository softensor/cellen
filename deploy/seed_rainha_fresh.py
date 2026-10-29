"""Create the fresh Rainha Njinga test families through Cellen's API.

Run only after ``deploy/reset_rainha_cellen.py`` has removed the old people
and debts. The seed refuses to run while the school still has guardians.

Every parent account gets the same password, taken from
``CELLEN_PARENT_PASSWORD``; the admin login uses ``CELLEN_DEMO_PASSWORD``.
Neither is written to the repo.

    CELLEN_DEMO_PASSWORD=... CELLEN_PARENT_PASSWORD=... \
        python deploy/seed_rainha_fresh.py

Optional environment:
    CELLEN_API_BASE     default https://167.235.158.77.nip.io/api/v1
    CELLEN_ADMIN_USER   default vmc@gmail.com
    CELLEN_SCHOOL_SLUG  default rainha-njinga
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import date

BASE = os.environ.get("CELLEN_API_BASE", "https://167.235.158.77.nip.io/api/v1")
ADMIN_USER = os.environ.get("CELLEN_ADMIN_USER", "vmc@gmail.com")
SCHOOL_SLUG = os.environ.get("CELLEN_SCHOOL_SLUG", "rainha-njinga")
PARENT_PASSWORD = os.environ.get("CELLEN_PARENT_PASSWORD", "")
token = ""

# (guardian first name, family name, sex, profession, [(child first, birth year, sex)])
FAMILIES = [
    ("Mariana", "Andrade", "F", "Gestora de projectos",
     [("Ana", 2019, "F"), ("Miguel", 2017, "M"), ("Sofia", 2014, "F")]),
    ("António", "Baptista", "M", "Engenheiro civil",
     [("Daniel", 2018, "M"), ("Beatriz", 2015, "F")]),
    ("Joana", "Costa", "F", "Médica",
     [("Lucas", 2019, "M"), ("Mariana", 2016, "F")]),
    ("Manuel", "Domingos", "M", "Comerciante",
     [("Gabriel", 2017, "M")]),
    ("Esperança", "Fernandes", "F", "Professora",
     [("Isabel", 2014, "F"), ("David", 2012, "M")]),
    ("Paulo", "Gomes", "M", "Contabilista",
     [("Helena", 2018, "F")]),
    ("Isabel", "José", "F", "Advogada",
     [("Rafael", 2016, "M"), ("Luana", 2013, "F")]),
    ("David", "Lopes", "M", "Enfermeiro",
     [("Mateus", 2015, "M")]),
    ("Helena", "Manuel", "F", "Arquitecta",
     [("Sara", 2019, "F"), ("Dinis", 2017, "M")]),
    ("Rafael", "Neto", "M", "Electricista",
     [("Eva", 2014, "F")]),
    ("Luana", "Paulo", "F", "Directora de recursos humanos",
     [("Tomás", 2018, "M"), ("Alice", 2016, "F"), ("Bruno", 2013, "M")]),
    ("Mateus", "Quissanga", "M", "Motorista",
     [("Carla", 2015, "F"), ("Eduardo", 2012, "M")]),
]


def api(path, data=None, method=None):
    request = urllib.request.Request(
        BASE + path,
        data=json.dumps(data).encode() if data is not None else None,
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + token},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"{path}: HTTP {exc.code}: {exc.read().decode()}") from None


def parent_username(index):
    return f"familia{index:02d}@rainha.invalid"


def main():
    global token
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    total_children = sum(len(children) for _, _, _, _, children in FAMILIES)
    if args.dry_run:
        for i, (first, last, sex, profession, children) in enumerate(FAMILIES, 1):
            print(f"familia{i:02d}  {first} {last}  ->  " + ", ".join(c[0] for c in children))
        print(f"{len(FAMILIES)} families, {total_children} children")
        return

    if not PARENT_PASSWORD:
        sys.exit("CELLEN_PARENT_PASSWORD is required (shared by every parent account)")
    admin_password = os.environ.get("CELLEN_DEMO_PASSWORD")
    if not admin_password:
        sys.exit("CELLEN_DEMO_PASSWORD is required (school admin login)")

    token = api(
        "/auth/login",
        {
            "username": ADMIN_USER,
            "password": admin_password,
            "school_slug": SCHOOL_SLUG,
        },
    )["access_token"]
    school = api("/schools/me")
    if school["slug"] != SCHOOL_SLUG:
        sys.exit(f"Logged into '{school['slug']}', expected '{SCHOOL_SLUG}'")

    existing = api("/guardians?limit=1")
    if existing:
        sys.exit(
            "The school already has guardians. Run deploy/reset_rainha_cellen.py "
            "first; this seed only fills an empty school."
        )

    years = api("/schools/school-years")
    active = [y for y in years if y.get("is_active")]
    if not active:
        sys.exit("No active school year; configure one before seeding.")
    year = sorted(active, key=lambda y: y.get("start_date") or "")[-1]

    schedules = api(f"/academic/schedules?school_year_id={year['id']}")
    if not schedules:
        turmas = api("/academic/turmas")
        if not turmas:
            sys.exit("No classes (turmas) configured; create at least one first.")
        schedules = [
            api("/academic/schedules", {"turma_id": t["id"], "school_year_id": year["id"]})
            for t in turmas
        ]
    schedules.sort(key=lambda s: s["id"])
    if not schedules:
        sys.exit("No schedule could be resolved for the active school year.")

    enrollment_date = year.get("start_date") or date.today().isoformat()
    child_number = 0
    created = []
    for i, (first, last, sex, profession, children) in enumerate(FAMILIES, 1):
        username = parent_username(i)
        guardian = api(
            "/guardians",
            {
                "first_name": first,
                "last_name": last,
                "sex": sex,
                "profession": profession,
                "city": "Luanda",
                "email": username,
                "username": username,
                "password": PARENT_PASSWORD,
            },
        )
        for child_first, birth_year, child_sex in children:
            child_number += 1
            child = api(
                "/children",
                {
                    "cedula": f"RNJ-2026-{child_number:03d}",
                    "first_name": child_first,
                    "last_name": last,
                    "birth_date": f"{birth_year}-{child_number % 12 + 1:02}-15",
                    "sex": child_sex,
                    "nationality": "Angolana",
                    "city": "Luanda",
                },
            )
            api(
                f"/guardians/{guardian['id']}/children",
                {
                    "child_id": child["id"],
                    "relationship_type": "mother" if sex == "F" else "father",
                    "is_primary_contact": True,
                },
            )
            schedule = schedules[(child_number - 1) % len(schedules)]
            api(
                "/academic/enrollments",
                {
                    "child_id": child["id"],
                    "schedule_id": schedule["id"],
                    "school_year_id": year["id"],
                    "enrollment_date": enrollment_date,
                    "enrollment_fee": 0,
                    "generate_invoice": False,
                },
            )
            created.append(child_first)
        print(f"familia{i:02d}  {first} {last}  ({len(children)} children)", flush=True)

    print()
    print(f"Created {len(FAMILIES)} families and {child_number} children.")
    print(f"Parent usernames: familia01@rainha.invalid .. familia{len(FAMILIES):02d}@rainha.invalid")
    print("All parent accounts use the CELLEN_PARENT_PASSWORD you supplied.")


if __name__ == "__main__":
    main()
