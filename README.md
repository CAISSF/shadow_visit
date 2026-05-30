# Veracross UI Query

Say we want to query every 8th grade student who is either visiting or touring a high school or is shadowing a high school student.

To achieve this in the UI, go to the LaunchPad > Daily Logistics > Attendance > General > Find Daily Attendance.

Click on the Query tab...<br>
Visualization: Data Grid

Click on the Fields tab...<br>
Add **Attendance Date** is on or after `09/01/25`<br>
~~Add **PERSON: Grade Level Enrolled At** in `Grade 8`<br>~~
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

# Similar API Query (macOS)

```bash
seq 0 290 | xargs --max-procs=2 -I {} bash -c '
  date=$(date -j -v+$1d -f "%Y-%m-%d" "2025-09-01" +%Y-%m-%d); \
  sleep 0.5; \
  curl --silent --get "https://api.veracross.com/{subdirectory}/v3/master_attendance" \
    --header "Authorization: Bearer {your_access_token}" \
    --data-urlencode "attendance_date=$date"
' _ {} | jq --slurp '[.[].data // [] | .[] | select(.notes // "" | test("shadow|visit|tour"; "i"))] | sort_by(.attendance_date, .person)' > output.json
```


Why this API query is similar to, but not equivalent to, the SQL Query is that this query cycles 290 times instead of filtering by date.

Sep 1 to mid-Jun is 280-290 days, and 300 requests every 3 minutes is the rate limit. Two parallel processes and half-second sleep between cycles is a sweet spot, since the rate also means a request speed limit of ~1.67 requests per second (with `--max-procs=2` and `sleep 0.5` the query will make ~0.8–2 requests per second).

# Testing

## Requirements

`school_route={subdirectory}`

> Example: "cais" in https://axiom.veracross.com/cais/

`client_id={your_client_id}`<br>
`client_secret={your_client_secret}`

> To obtain these credentials, a user with a OAuth_App_Admin supplemental security role must create an internal integration in Identity & Access Management

## Retrieve Access Token

In a terminal emulator (e.g., macOS Terminal), run the command:

```bash
export access_token=$(curl --silent --request POST https://accounts.veracross.com/{subdirectory}/oauth/token \
  --data "grant_type=client_credentials" \
  --data "client_id={your_client_id}" \
  --data "client_secret={your_client_secret}" \
  --data "scope=master_attendance:list" | jq --raw-output '.access_token')
```

Command will retrieve a new access token and store is value in variable: `access_token`. Used tokens expire in 1 hour, so re-run this command after each token expires.

## Run API Query

See "Similar API Query" above, and be patient. You will retrieve a JSON response in a moment, and you review it in the `output.json` file. (You can also output the response directly in the terminal emulator, however JSON responses can be exceptionally long.)

If the JSON response is empty (i.e., `[]`), either the query found nothing or the access token has expired. To check if the access token has expired, run the command:

```bash
curl --silent --request GET \
  --url "https://api.veracross.com/$school_route/v3/master_attendance" \
  --header "Authorization: Bearer $access_token" | jq .error
```

It will return either `"The provided access token has expired"` or, if not expired, `null`. 

Again, query requests are also subject to rate limits of 300 requests every 3 minutes, also meaning a request speed limit of ~1.67 requests per second.

# Suggestion

1. In each command and query, replace:<p>
`{subdirectory}` &rarr; `$school_route`<br>
`{your_client_id}` &rarr; `$client_id`<br>
`{your_client_secret}` &rarr; `$client_secret`<br>
`{your_access_token}` &rarr; `$access_token`
2. Either export the environment variables: `school_route`, `client_id` and `client_secret` with their values OR<p>
(And this what I do) Place the environment variables and their values in a `.env` file, and export them by running: `export $(grep --invert-match '^#' .env | xargs)`
3. _Then_ run the command to retrieve the access token, and then run the API query. 

> The command to retrieve the access token exports `access_token` and its value for you, so do not export it manually or place it in `.env`. Let it be.

# To Do

Refine selection more, since not all visits/tours are to schools.

# Reference

[Veracross API Documentation](https://api-docs.veracross.com/) (e.g., endpoints, rate limits)