import 'package:flutter/material.dart';

import 'school.dart';

/// Segment-aware terminology and icons for the app.
///
/// Usage:
///   final terms = SchoolTerms.of(school);
///   Text(terms.student)      // 'Criança' or 'Aluno'
///   Icon(terms.studentIcon)  // child_care or person
class SchoolTerms {
  final String student;       // singular
  final String students;      // plural
  final String teacher;       // singular
  final String teachers;      // plural
  final String classroom;     // 'Turma'
  final String attendance;    // 'Presenças'
  final IconData studentIcon;
  final IconData teacherIcon;
  final IconData classroomIcon;
  final bool isK12;

  const SchoolTerms._({
    required this.student,
    required this.students,
    required this.teacher,
    required this.teachers,
    required this.classroom,
    required this.attendance,
    required this.studentIcon,
    required this.teacherIcon,
    required this.classroomIcon,
    required this.isK12,
  });

  factory SchoolTerms.of(School? school) {
    final segment = school?.segment ?? 'preschool';
    final k12 = school?.hasFeature('timetable_k12') ?? false;

    switch (segment) {
      case 'primary':
      case 'secondary':
      case 'combined':
        return SchoolTerms._(
          student: 'Aluno',
          students: 'Alunos',
          teacher: 'Professor',
          teachers: 'Professores',
          classroom: 'Turma',
          attendance: 'Presenças',
          studentIcon: Icons.person_outlined,
          teacherIcon: Icons.school_outlined,
          classroomIcon: Icons.class_outlined,
          isK12: true,
        );
      case 'full':
        // Combined preschool + K12 — default to K12 terms when timetable_k12 enabled
        return k12
            ? SchoolTerms._(
                student: 'Aluno',
                students: 'Alunos',
                teacher: 'Professor',
                teachers: 'Professores',
                classroom: 'Turma',
                attendance: 'Presenças',
                studentIcon: Icons.person_outlined,
                teacherIcon: Icons.school_outlined,
                classroomIcon: Icons.class_outlined,
                isK12: true,
              )
            : SchoolTerms._preschool();
      default: // 'preschool'
        return SchoolTerms._preschool();
    }
  }

  factory SchoolTerms._preschool() => const SchoolTerms._(
        student: 'Criança',
        students: 'Crianças',
        teacher: 'Educador',
        teachers: 'Educadores',
        classroom: 'Grupo',
        attendance: 'Presenças',
        studentIcon: Icons.child_care,
        teacherIcon: Icons.face_outlined,
        classroomIcon: Icons.groups_outlined,
        isK12: false,
      );
}
