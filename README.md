# Running Veracross Query Using API

## TL;DR

Run the following commands:

```bash
mkdir temp/

cat > fetch_attendance.sh << 'EOF'
date=$(date -j -v+$1d -f "%Y-%m-%d" "2025-09-01" +%Y-%m-%d); \
sleep 0.5; \
curl --silent --get "https://api.veracross.com/$school_route/v3/master_attendance" \
  --header "Authorization: Bearer $access_token" \
  --header "X-Page-Size: 1000" \
  --data-urlencode "attendance_date=$date" > temp/$1.json
EOF

chmod +x fetch_attendance.sh

seq 0 289 | xargs --max-procs=2 -I N bash ./fetch_attendance.sh N

jq --slurp '[.[].data // [] | .[] | select(.notes // "" | test("shadow|visit|tour"; "i"))] | sort_by(.attendance_date, .person)' temp/*.json > output.json

rm -rf temp/
```

The commands will create a script, make it executable, execute the query, output results, and clean itself up.

## Background

### Running Veracross Query Using UI

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

### Equivalent SQL Query

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

### Similar API Query (macOS)

```bash
seq 0 289 | xargs --max-procs=2 -I N bash -c '
  date=$(date -j -v+Nd -f "%Y-%m-%d" "2025-09-01" +%Y-%m-%d); \
  sleep 0.5; \
  curl --silent --get "https://api.veracross.com/{subdirectory}/v3/master_attendance" \
    --header "Authorization: Bearer {your_access_token}" \
    --header "X-Page-Size: 1000" \
    --data-urlencode "attendance_date=$date" > N.json
'

jq --slurp '[.[].data // [] | .[] | select(.notes // "" | test("shadow|visit|tour"; "i"))] | sort_by(.attendance_date, .person)' *.json > output.json
```

Why this API query is similar to, but not equivalent to, the SQL Query is that this query cycles 290 times (0, 1, 2, ..., 289) instead of filtering by date.

Sep 1 to mid-Jun is 280-290 days, and 300 requests every 3 minutes is the rate limit. Two parallel processes and half-second sleep between cycles is a sweet spot, since the rate also means a request speed limit of ~1.67 requests per second (with `--max-procs=2` and `sleep 0.5` the query will make ~0.8–2 requests per second).

Why generate multiple temporary JSON files (`0.json`, `1.json`, `2.json`, etc.) and then combine them into `output.json`? Otherwise, the parallel processes corrupted `output.json`

### Testing

#### Retrieve Credentials

School route:<br>
`school_route={subdirectory}`

Example: "cais" (sans quotes) in https://axiom.veracross.com/cais/

Client ID and Secret:<br>
`client_id={your_client_id}`<br>
`client_secret={your_client_secret}`

To obtain the client ID and secret, a user with a OAuth_App_Admin supplemental security role must create an internal integration in Identity & Access Management

#### Retrieve Access Token

In a terminal emulator (e.g., macOS Terminal), run the command:

```bash
export access_token=$(curl --silent --request POST https://accounts.veracross.com/{subdirectory}/oauth/token \
  --data "grant_type=client_credentials" \
  --data "client_id={your_client_id}" \
  --data "client_secret={your_client_secret}" \
  --data "scope=master_attendance:list" | jq --raw-output '.access_token')
```

Command will retrieve a new access token and store is value in variable: `access_token`. Used tokens expire in 1 hour, so re-run this command after each token expires.

#### Run API Query (macOS)

You will need to modify the query above (see "Similar API Query"), first, otherwise the terminal emulator will complain: `xargs: command line cannot be assembled, too long`

Place the query's bash command in a shell script, for example...<br>
`fetch_attendance.sh`:
```bash
date=$(date -j -v+$1d -f "%Y-%m-%d" "2025-09-01" +%Y-%m-%d); \
sleep 0.5; \
curl --silent --get "https://api.veracross.com/{subdirectory}/v3/master_attendance" \
  --header "Authorization: Bearer {your_access_token}" \
  --header "X-Page-Size: 1000" \
  --data-urlencode "attendance_date=$date" > $1.json
```

Make the script executable: `chmod +x fetch_attendance.sh`<br>
Alternatively: `chmod 755 fetch_attendance.sh` (same result)

Then, run the query using the script:<br>
```bash
seq 0 289 | xargs --max-procs=2 -I N bash ./fetch_attendance.sh N

jq --slurp '[.[].data // [] | .[] | select(.notes // "" | test("shadow|visit|tour"; "i"))] | sort_by(.attendance_date, .person)' *.json > output.json
```
Be patient! You will retrieve a JSON response in a moment, and you can review it in the `output.json` file. (You can also output the response directly in the terminal emulator, however JSON responses can be exceptionally long.)

> In the shell script, I have also replaced `N` with `$1`, so that `xargs` passes the value of `N` (0, 1, 2, ..., 289) into the script as argument `$1`. (Any additional arguments must be `$2`, `$3`, `$4`, etc.)<p>
> The second `N` after `fetch_attendance.sh` in the `xargs` command is what changes value and is what is passed into the script. The first `N` after `-I` defines the placeholder name, so just make sure to match the placeholders.

##### Empty Responses

If the JSON response is empty (i.e., `[]`), either the query found nothing or the access token has expired. To check if the access token has expired, run the command:

```bash
curl --silent --request GET \
  --url "https://api.veracross.com/$school_route/v3/master_attendance" \
  --header "Authorization: Bearer $access_token" | jq .error
```

It will return either `"The provided access token has expired"` or, if not expired, `null`. 

Again, query requests are also subject to rate limits of 300 requests every 3 minutes, also meaning a request speed limit of ~1.67 requests per second.

##### Suggestions

1. In each command and query, replace:<p>
`{subdirectory}` &rarr; `$school_route`<br>
`{your_client_id}` &rarr; `$client_id`<br>
`{your_client_secret}` &rarr; `$client_secret`<br>
`{your_access_token}` &rarr; `$access_token`
2. Either export the environment variables: `school_route`, `client_id` and `client_secret` with their values OR<p>
(And this what I do) Place the environment variables and their values in a `.env` file, and export them by running: `export $(grep --invert-match '^#' .env | xargs)`
3. _Then_ run the command to retrieve the access token, and then run the API query.
4. Better yet, create a temporary folder: `mkdir temp/`, generate the multiple JSON files in there: `$1.json` &rarr; `temp/$1.json` and `*.json` &rarr; `temp/*.json` respectively, and once you complete your query clean up the temporary JSON files with `rm -rf temp/`

> The command to retrieve the access token exports `access_token` and its value for you, so do not export it manually or place it in `.env`. Let it be.

## Format JSON Response like Veracross UI Response (Optional)

Run the command:

```bash
jq --raw-output '
  def format_date: 
    split("-") | .[1] + "/" + .[2] + "/" + (.[0][2:]);

  def format_category: 
    if . == 0 then "Present"
    elif . == 1 then "Absence"
    elif . == 2 then "Tardy"
    elif . == 3 then "Early Dismissal"
    else "Unknown" end;

  def format_time: 
    if . == null then ""
    else
      split("T")[1] | split(":")[0:2] |
      (.[0] | tonumber) as $h | .[1] as $m |
      if $h < 12 then
        (if $h == 0 then "12" else ($h | tostring) end) + ":" + $m + "am"
      elif $h == 12 then "12:" + $m + "pm"
      else (($h - 12) | tostring) + ":" + $m + "pm"
      end
    end;

  ["date","person","attendance_category","late_arrival_time","early_dismissal_time","notes"],
  ["----","------","-------------------","----------------","--------------------","-----"],
  (.[] | [(.attendance_date | format_date), .person, (.attendance_category | format_category), (.late_arrival_time | format_time), (.early_dismissal_time | format_time), .notes])
  | @tsv' output.json \
  | sed 's/^/|/' \
  | sed 's/\t/|/g' \
  | sed 's/$/|/' > output.md
```

Open `output.md`

`jq` is a command-line tool for parsing, filtering, and transforming JSON, and `@tsv` is a jq formatter. `jq` extracts arrays from `output.json`, and `@tsv` converts them into tab separated strings.

`sed` is a command-line tool that reads text line by line and applies additional transformations; its basic syntax is `sed 's/find/replace/g'`. `^` means start of line; `\t` means tab character; and `$` means end of line.

# To Do

- Refine selection more, since not all visits/tours are to schools.
- Optimize to only look for changes?

# Reference

[Veracross API Documentation](https://api-docs.veracross.com/) (e.g., endpoints, rate limits)