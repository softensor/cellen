"""Academic, finance and media examples; run after core pupils exist."""
import os
import json
import uuid
import urllib.request
from pathlib import Path
from datetime import date, timedelta
import seed_rainha_demo as d

d.JOURNAL = d.STATE_DIR / 'cellen-rainha-demo-extras-journal.json'
if d.JOURNAL.exists():
    d.state.update(json.loads(d.JOURNAL.read_text()))
d.token = d.api('/auth/login',dict(username='vmc@gmail.com',password=os.environ['CELLEN_DEMO_PASSWORD'],school_slug='rainha-njinga'))['access_token']
assert d.api('/schools/me')['slug']=='rainha-njinga'
users={u['username']:u for u in d.api('/schools/users')}
teacher=users['kvt@gmail.com']['employee_id']
year=next(y for y in d.api('/schools/school-years') if y['is_active'])
today=date.today()
note='DEMO — registo fictício para apresentação.'
subjects=[]
for i,name in enumerate(['Língua Portuguesa','Matemática','Estudo do Meio','Educação Visual']):
    subjects.append(d.add(f'subject-{i}','/grades/subjects',dict(name=name+' — Demo',code=f'DEMO-{i+1}',order=i)))
existing_periods=d.api('/timetable/periods')
periods=[]
for i in range(4):
    # Reuse the school's existing timetable template when available.
    existing=next((p for p in existing_periods if p['period_number']==i+1 and not p['is_break']),None)
    periods.append(existing or d.add(f'period-{i}','/timetable/periods',dict(period_number=i+1,name=f'{i+1}.ª Aula',start_time=f'{8+i:02}:00',end_time=f'{8+i:02}:45')))
for group in [1,2]:
    turma=d.state[f'class-{group}'];schedule=d.state[f'schedule-{group}']
    for i,subject in enumerate(subjects):
        d.add(f'turma-subject-{group}-{i}','/grades/turma-subjects',dict(turma_id=turma['id'],subject_id=subject['id'],school_year_id=year['id'],teacher_id=teacher))
        for day in range(5):
            # Each demo class uses different periods for its named teacher.
            if group==2 and i<2 or group==1 and i>=2:continue
            d.add(f'cell-{group}-{i}-{day}','/timetable/grid/cells',dict(schedule_id=schedule['id'],day_of_week=day,period_id=periods[i]['id'],subject_id=subject['id'],employee_id=teacher,room=turma['room']))
    marks=[]
    for n in range(24):
        if n%3 != group:continue
        for i,subject in enumerate(subjects):
            marks.append(dict(enrollment_id=d.state[f'enrollment-{n}']['id'],subject_id=subject['id'],trimester=1,mac_grade=11+(n+i)%9,exam_grade=12+(n+i)%8,notes=note))
    d.add(f'marks-{group}','/grades/marks/bulk',dict(marks=marks))
    i=0 if group==1 else 2
    for delta in [0,1,4]:
        d.add(f'lesson-attendance-{group}-{delta}','/lesson-attendance/session/bulk',dict(schedule_id=schedule['id'],subject_id=subjects[i]['id'],date=(today-timedelta(days=delta)).isoformat(),period_id=periods[i]['id'],records=[dict(child_id=d.state[f'pupil-{n}']['id'],status=['present','late','absent','justified'][n%4] if delta else 'present',notes=note) for n in range(24) if n%3==group]))

def upload(key,path,fields,filename,mime,content):
    if key in d.state:return d.state[key]
    boundary='cellen-demo-'+uuid.uuid4().hex
    body=b''
    for name,value in fields.items():
        body+=f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
    body+=f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{filename}"\r\nContent-Type: {mime}\r\n\r\n'.encode()+content+f'\r\n--{boundary}--\r\n'.encode()
    req=urllib.request.Request(d.BASE+path,data=body,headers={'Authorization':'Bearer '+d.token,'Content-Type':'multipart/form-data; boundary='+boundary})
    d.state[key]=json.load(urllib.request.urlopen(req,timeout=60));d.save();print('Created',key,flush=True)
    return d.state[key]

def pdf(title,lines):
    def escape(s):return s.replace('\\','\\\\').replace('(','\\(').replace(')','\\)')
    text='BT /F1 18 Tf 50 780 Td ('+escape(title)+') Tj /F1 12 Tf '
    for line in lines:text+='0 -30 Td ('+escape(line)+') Tj '
    stream=(text+'ET').encode('cp1252')
    objects=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'\nendstream']
    result=b'%PDF-1.4\n'; offsets=[0]
    for n,obj in enumerate(objects,1):offsets.append(len(result));result+=f'{n} 0 obj\n'.encode()+obj+b'\nendobj\n'
    start=len(result);result+=b'xref\n0 6\n0000000000 65535 f \n'
    result+=b''.join(f'{v:010} 00000 n \n'.encode() for v in offsets[1:])
    return result+f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{start}\n%%EOF'.encode()

for i,(title,lines) in enumerate([
    ('Guia das famílias',['Entrada: 07h30 | Saída: 15h30','Trazer material identificado e garrafa de água.','Consultar a caderneta e o calendário na aplicação.']),
    ('Plano de actividades',['Segunda: leitura e expressão oral','Quarta: ciência e descoberta','Sexta: desporto e expressão artística']),
    ('Ementa semanal',['Pequeno-almoço: papa de milho e fruta','Almoço: arroz, frango ou peixe e legumes','Lanche: iogurte e banana'])]):
    upload(f'document-{i}','/documents',dict(name=title+' — Demo',description=note,category='general',target='all'),f'demo-rnj-{i}.pdf','application/pdf',pdf('Rainha Njinga - '+title,['DEMONSTRAÇÃO - documento fictício',*lines]))
image_path=Path(__file__).parent/'demo-assets'/'rainha-activity.jpg'
if image_path.exists():
    for group in range(3):
        upload(f'photo-{group}','/photos',dict(caption='Ciência e natureza — ilustração fictícia de demonstração',turma_id=d.state[f'class-{group}']['id'],child_id=d.state[f'pupil-{group}']['id'],photo_date=today.isoformat()),'demo-actividade.jpg','image/jpeg',image_path.read_bytes())
print('Academic and media examples complete',flush=True)
