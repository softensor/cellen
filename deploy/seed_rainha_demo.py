"""Add presentation data through Cellen's API; never delete existing records.

Run with CELLEN_DEMO_PASSWORD set to the existing vmc school-admin password.
The local journal makes reruns resume already-created records without duplicates.
"""
import json
import os
import secrets
import urllib.request
import urllib.error
from datetime import date, timedelta
from pathlib import Path

BASE = 'https://167.235.158.77.nip.io/api/v1'
STATE_DIR = Path(__file__).resolve().parents[1] / '.demo-state'
STATE_DIR.mkdir(mode=0o700, exist_ok=True)
JOURNAL = Path(os.environ.get('CELLEN_DEMO_JOURNAL', str(STATE_DIR / 'cellen-rainha-demo-journal.json')))
state = json.loads(JOURNAL.read_text()) if JOURNAL.exists() else {}
token = ''

def api(path, data=None, method=None):
    request = urllib.request.Request(BASE + path, data=json.dumps(data).encode() if data is not None else None,
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f'{path}: HTTP {exc.code}: {exc.read().decode()}') from None

def save():
    JOURNAL.write_text(json.dumps(state, ensure_ascii=False, indent=2))
    JOURNAL.chmod(0o600)

def add(key, path, data, method=None):
    if key not in state:
        state[key] = api(path, data, method)
        save()
        print('Created', key, flush=True)
    return state[key]

def main():
    global token
    token = api('/auth/login', dict(username='vmc@gmail.com', password=os.environ['CELLEN_DEMO_PASSWORD'], school_slug='rainha-njinga'))['access_token']
    school = api('/schools/me')
    assert school['slug'] == 'rainha-njinga' and school['id'] == '65794af5-2831-4709-9b53-437bb5d50515'
    assert not school['wa_enabled'], 'Demo expects external WhatsApp delivery disabled'
    users = {u['username']: u for u in api('/schools/users')}
    teacher = users['kvt@gmail.com']['employee_id']
    staff = users['bsd@gmail.com']['employee_id']
    guardian = users['mpa@something.com']['guardian_id']
    year = next(y for y in api('/schools/school-years') if y['is_active'])
    today = date.today()
    monday = today - timedelta(days=today.weekday())
    note = 'DEMO — registo fictício para apresentação da escola.'
    schedules = []
    classes = []
    for i, (name, level) in enumerate([('Girassóis — Demo', 'Jardim de Infância'), ('3.ª Classe A — Demo', '3.ª Classe'), ('7.ª Classe A — Demo', '7.ª Classe')]):
        turma = add(f'class-{i}', '/academic/turmas', dict(name=name, level=level, room=f'D{i+1}', max_capacity=25))
        classes.append(turma)
        schedule = add(f'schedule-{i}', '/academic/schedules', dict(turma_id=turma['id'], school_year_id=year['id']))
        schedules.append(schedule)
        add(f'teacher-{i}', f"/academic/schedules/{schedule['id']}/teachers", dict(employee_id=teacher))
    pupils = []
    names = [('Ana','Andrade'),('Miguel','Andrade'),('Sofia','Andrade'),('Daniel','Baptista'),('Beatriz','Costa'),('Lucas','Domingos'),('Mariana','Fernandes'),('Gabriel','Gomes'),('Isabel','José'),('David','Lopes'),('Helena','Manuel'),('Rafael','Neto'),('Luana','Paulo'),('Mateus','Quissanga'),('Sara','Santos'),('Dinis','Tavares'),('Eva','Vicente'),('Tomás','Xavier'),('Alice','Afonso'),('Bruno','Barros'),('Carla','Correia'),('Eduardo','Dias'),('Flora','Esteves'),('Joel','Faria')]
    for i, (first,last) in enumerate(names):
        group = i % 3
        child = add(f'pupil-{i}', '/children', dict(cedula=f'DEMO-RNJ-{i+1:03}', first_name=first, last_name=last,
            birth_date=f'{today.year-[4,8,12][group]}-{i%12+1:02}-15', sex='F' if i%2==0 else 'M', nationality='Angolana', city='Luanda', special_needs=note))
        if i < 3:
            gid = guardian
        else:
            g = add(f'guardian-{i}', '/guardians', dict(first_name=['Maria','António','Joana'][group],last_name=last, city='Luanda',
                email=f'rnj.demo.{i+1}@example.invalid',username=f'rnj.demo.{i+1}@example.invalid',password=secrets.token_urlsafe(24), profession='Encarregado de educação — Demo'))
            gid = g['id']
        add(f'link-{i}', f'/guardians/{gid}/children', dict(child_id=child['id'], relationship_type='legal_guardian',is_primary_contact=True))
        enrollment = add(f'enrollment-{i}', '/academic/enrollments', dict(child_id=child['id'],schedule_id=schedules[group]['id'],school_year_id=year['id'],enrollment_date=monday.isoformat(),generate_invoice=False))
        pupils.append((child,gid,enrollment,group))
    for delta in range(10):
        day = today-timedelta(days=delta)
        if day.weekday()>4: continue
        add(f'attendance-{day}', '/attendance/bulk', dict(date=day.isoformat(),records=[dict(child_id=c['id'],status='absent' if (i+delta)%11==0 else 'present',notes=note) for i,(c,g,e,k) in enumerate(pupils)]))
    for i,(child,gid,enrollment,group) in enumerate(pupils):
        if group == 0:
            for delta in [0,1,4]:
                day=today-timedelta(days=delta)
                add(f'diary-{i}-{delta}', '/cadernetas', dict(child_id=child['id'],teacher_id=teacher,report_date=day.isoformat(),breakfast_rating='Bem',lunch_rating='Muito Bem',snack_rating='Bem',had_nap=True,behavior='Bem-disposto e participativo',activities='Pintura, leitura de histórias e jogos de construção.',general_observations=note))
            add(f'evaluation-{i}', '/evaluations',dict(child_id=child['id'],school_year_id=year['id'],evaluation_period='Diagnóstico — Demo',evaluation_date=today.isoformat(),cognitive=4,motor=4,language=3,social_emotional=4,creativity=5,autonomy=3,overall_rating='good',observations=note,areas_to_improve='Reforçar a autonomia nas rotinas diárias.',objectives_next_period='Reconhecer cores e contar até dez.'))
        if i<6:
            add(f'health-{i}', '/health-events',dict(child_id=child['id'],event_date=(today-timedelta(days=i)).isoformat(),event_type='observation',description=note+' Observação de rotina, sem queixas.',parent_notified=False,action_taken='Registada observação para acompanhamento.'))
            add(f'vaccine-{i}', '/immunizations',dict(child_id=child['id'],vaccine_name='Boletim de vacinação — Demo',administered_at=(today-timedelta(days=180)).isoformat(),due_date=(today+timedelta(days=30+i)).isoformat(),dose_number=1,notes=note))
            add(f'incident-{i}', '/incidents/',dict(child_id=child['id'],description=note+' Desentendimento durante jogo, resolvido com mediação.',severity='minor',incident_date=(today-timedelta(days=i)).isoformat(),action_taken='Conversa orientada sobre partilha e respeito.'))
            add(f'pickup-{i}', '/pickup-authorizations',dict(child_id=child['id'],authorized_person_name=f'Maria {child["last_name"]} — Demo',relationship='Avó',notes=note))
            for delta in range(3):
                add(f'meal-{i}-{delta}', '/pickup-authorizations/meal-orders',dict(child_id=child['id'],order_date=(today+timedelta(days=delta)).isoformat(),meal_type='lunch',quantity=1))
    for i,name in enumerate(['Leitura de histórias — Demo','Expressão plástica — Demo','Jogos motores — Demo']):
        activity=add(f'activity-{i}','/academic/activities',dict(name=name,description=note))
        for day in range(5):
            add(f'activity-slot-{i}-{day}',f"/academic/schedules/{schedules[0]['id']}/slots",dict(day_of_week=day,slot_time=f'{8+i:02}:00:00',activity_id=activity['id']))
    foods=[]
    for i,(name,kind) in enumerate([('Papa de milho — Demo','breakfast'),('Arroz com frango e legumes — Demo','main'),('Sopa de legumes — Demo','soup'),('Banana e iogurte — Demo','snack'),('Peixe com batata-doce — Demo','main'),('Feijão com arroz — Demo','main')]):
        foods.append(add(f'food-{i}','/food/foods',dict(name=name,description=note,food_type=kind)))
    for k,level in enumerate(['Jardim de Infância','3.ª Classe','7.ª Classe']):
        add(f'menu-{k}','/food/menus',dict(level=level,start_date=monday.isoformat(),end_date=(monday+timedelta(days=11)).isoformat(),items=[dict(day_of_week=d,meal_type=m,food_id=foods[f]['id']) for d in range(5) for m,f in [('breakfast',0),('lunch',[1,4,5][d%3]),('snack',3)]]))
    for i,title in enumerate(['Feira de ciências','Encontro de famílias','Dia do desporto']):
        add(f'event-{i}','/events/',dict(title=title+' — Demo',description=note,start_date=(today+timedelta(days=7*(i+1))).isoformat(),event_type='school_event',location='Escola Rainha Njinga'))
        add(f'announcement-{i}','/announcements',dict(title=title+' — Demonstração',body=note+' Consulte o calendário escolar para conhecer as actividades previstas.',target='all',pinned=i==0))
        add(f'trip-{i}','/trip-authorizations',dict(child_id=pupils[i][0]['id'],title='Visita ao museu — Demo',trip_date=(today+timedelta(days=14)).isoformat(),destination='Museu de História Natural',description=note,departure_time='09:00',return_time='12:00',deadline_date=(today+timedelta(days=10)).isoformat()))
        add(f'appointment-{i}','/appointments',dict(employee_id=teacher,child_id=pupils[i][0]['id'],title='Acompanhamento pedagógico — Demo',notes=note,proposed_date=(today+timedelta(days=i+3)).isoformat(),proposed_time=f'{14+i}:00'))
    for i,employee in enumerate([teacher,staff]):
        add(f'absence-{i}','/absences',dict(employee_id=employee,school_year_id=year['id'],absence_date=(today-timedelta(days=14+i)).isoformat(),absence_type='personal',justified=True,justification='Assunto pessoal — exemplo fictício.',notes=note))
    for i,(subject,recipient) in enumerate([('Adaptação e aprendizagem','mpa@something.com'),('Preparação da reunião pedagógica','kvt@gmail.com'),('Organização da cantina','bsd@gmail.com'),('Resumo da semana escolar','rnj@gmail.com')]):
        add(f'thread-{i}','/messages/threads',dict(subject=subject+' — Demo',participant_ids=[users[recipient]['id']],message=note+' Bom dia! Este exemplo apresenta a comunicação entre os perfis da escola.'))
    print('Core demo data complete', flush=True)

if __name__ == '__main__':
    main()
