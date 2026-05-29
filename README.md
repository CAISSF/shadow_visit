# Veracross UI Query

Say we want to query every 8th grade student who is either visiting or touring a high school or is shadowing a high school student.

To achieve this in the UI, go to the LaunchPad > Daily Logistics > Attendance > General > Find Daily Attendance.

Click on the Query tab...<br>
Visualization: Data Grid

Click on the Fields tab...<br>
Add **Attendance Date** is on or after 09/01/25<br>
~~Add **PERSON: Grade Level Enrolled At** in Grade 8<br>~~
~~> PERSON: Grade Level Enrolled At has a One-To-Many Relationship because some students are in multiple preschool levels. (Not an issue for Grade 8.)~~ Visits/tours start in Grade 8, so this filter is redundant.

Add **Person**<br>
Add **Attendance Category**<br>
Add **Late Arrival Time**<br>
Add **Early Dismissal Time**<br>
Add **Notes** contains "shadow," "visit" or "tour"<br>
> For Notes, input criteria value: `shadow; visit; tour`. Every school visit/tour entry contains at least one of these three words.

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
FROM master_attendance
WHERE attendance_date >= DATE '2025-09-01'
  AND (
    notes ILIKE '%shadow%'
    OR notes ILIKE '%visit%'
    OR notes ILIKE '%tour%'
  )
ORDER BY attendance_date, person;
```
An SQL-like query like this would produce a data grid already.

# Equivalent API Query

```bash
for date in $(seq -f "%02g" 1 30 | awk '{printf "2025-09-%s\n", $1}'); do
  curl -s -G "https://api.veracross.com/{school_route}/v3/master_attendance" \
    -H "Authorization: Bearer {your_access_token}" \
    -H "X-Page-Size: 1000" \
    --data-urlencode "attendance_date=$date"
done | jq -s '[.[].data[] | select(.notes // "" | test("shadow|visit|tour"; "i"))] | sort_by(.attendance_date, .person)'
```

# To Do

Test the API call