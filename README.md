# Veracross UI Query

Say we want to query every 8th grade student who is either visiting or touring a high school or is shadowing a high school student.

To achieve this in the UI, go to the LaunchPad > Daily Logistics > Attendance > General > Find Daily Attendance.

Click on the Query tab...<br>
Visualization: Data Grid

Click on the Fields tab...<br>
Add **Attendance Date** is on or after 09/01/25<br>
Add **PERSON: Grade Level Enrolled At** in Grade 8<br>
> PERSON: Grade Level Enrolled At has a One-To-Many Relationship because some students are in multiple preschool levels. (Not an issue for Grade 8.)

Add **Person**<br>
Add **Attendance Category**<br>
Add **Late Arrival Time**<br>
Add **Early Dismissal Time**<br>
Add **Notes** contains "visit," or "tour," or "shadow"<br>
> For Notes, input criteria value: `visit; tour; shadow`. Every school visit/tour entry contains at least one of these three words.

Ascending order by Attendance Date, then ascending order by Person

# Equivalent SQL Query

Veracross UI does not permit an SQL-like query. However, if it had, then the query would look like:

```sql
SELECT
  attendance_date,
  person,
  attendance_category,
  late_arrival_time,
  early_dismissal_time,
  notes
FROM daily_attendance
WHERE attendance_date >= DATE '2025-09-01'
  AND grade_level_enrolled_at IN ('Grade 8')
  AND (
    notes ILIKE '%visit%'
    OR notes ILIKE '%tour%'
    OR notes ILIKE '%shadow%'
  )
ORDER BY attendance_date, person;
```
An SQL-like query like this would produce a data grid already.

# Equivalent API Query

```bash
GET https://api.veracross.com/{school_route}/v3/daily-attendance?
  select=attendance_date,person,attendance_category,late_arrival_time,early_dismissal_time,notes&
  attendance_date=gte.2025-09-01&
  grade_level_enrolled_at=eq.Grade%208&
  or=(notes.ilike.*visit*,notes.ilike.*tour*,notes.ilike.*shadow*)&
  order=attendance_date.asc,person.asc
```

# To Do

Test the API call