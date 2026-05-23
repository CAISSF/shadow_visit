# Veracross UI Query

Say we want to query every 8th grade student who is either visiting or touring a high school or is shadowing a high school student.

To achieve this in the UI, go to the LaunchPad > Daily Logistics > Attendance > General > Find Daily Attendance.

Click on the Query tab...<br>
Visualization: Data Grid

Click on the Fields tab...<br>
Add **Attendance Date** is on or after 09/01/25<br>
Add **PERSON: Grade Level Enrolled At** in Grade 8<br>
Add **Person**<br>
Add **Attendance Category**<br>
Add **Late Arrival Time**<br>
Add **Early Dismissal Time**<br>
Add **Notes** contains "visit," or "tour," or "shadow"<br>
> For Notes, input criteria value: `visit; tour; shadow`

Ascending order by Attendance Date, then ascending order by Person