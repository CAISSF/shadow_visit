# Running Veracross Query Using API

Say we want to query every 8th grade student who is either visiting or touring a high school or is shadowing a high school student.

## TL;DR

### Step 1: Set Credentials

Retrieve your credentials (see "Testing"), and then in a terminal emulator (e.g., macOS Terminal) run these commands:

```bash
echo "school_route={subdirectory}" >> .env && \
echo "client_id={your_client_id}" >> .env && \
echo "client_secret={your_client_secret}" >> .env && \

export $(grep --invert-match '^#' .env | xargs)
```

### Step 2: Get Access Token (Expires in 1 Hour)

Run this command:

```bash
export access_token=$(curl --silent --request POST https://accounts.veracross.com/$school_route/oauth/token \
  --data "grant_type=client_credentials" \
  --data "client_id=$client_id" \
  --data "client_secret=$client_secret" \
  --data "scope=master_attendance:list directory.student:list" | jq --raw-output '.access_token')
```

### Step 3: Create a Script

```bash
cat > fetch_attendance.sh << 'EOF'
date=$(date -j -v+$1d -f "%Y-%m-%d" "2025-09-01" +%Y-%m-%d); \
sleep 0.5; \
curl --silent --get "https://api.veracross.com/$school_route/v3/master_attendance" \
  --header "Authorization: Bearer $access_token" \
  --header "X-Page-Size: 1000" \
  --data-urlencode "attendance_date=$date" > temp/$1-attendance.json
EOF && \

chmod +x fetch_attendance.sh
```

### Step 4A: Retrieve Student Records

```bash
mkdir -p temp/ && \

start="2025-09-01" && \
today=$(date +%Y-%m-%d) && \
end="2026-06-11" && \

today=$(( ($(date -j -f "%Y-%m-%d" "$today" +%s) - $(date -j -f "%Y-%m-%d" "$start" +%s)) / 86400 )) && \
end=$(( ($(date -j -f "%Y-%m-%d" "$end" +%s) - $(date -j -f "%Y-%m-%d" "$start" +%s)) / 86400 )) && \

seq $today $end | xargs --max-procs=2 -I N bash ./fetch_attendance.sh N && \

curl --silent --get "https://api.veracross.com/$school_route/v3/directory/student" \
  --header "Authorization: Bearer $access_token" \
  --header "X-Page-Size: 1000" \
  --data-urlencode "grade_level=8" > temp/grade8.json
```

### Step 4B: Filter the Student Records

Use regular expressions, and focus on records that have changed:

```bash
jq --slurp --slurpfile names temp/grade8.json '
  ($names[0].data | map(.student_id) | map(tostring)) as $ids |
  [.[].data // [] | .[] | select(.person_id | tostring | IN($ids[]))] |
  sort_by(.attendance_date, .person)
' temp/*-attendance.json > temp/filtered8.json && \

if [ -f output.json ]; then
  jq 'map({key: (.id | tostring), value: .notes}) | from_entries' output.json > temp/reference.json && \

  jq --slurpfile old temp/reference.json '
  [.[] | . as $record | select($old[0][$record.id | tostring] != null and $old[0][$record.id | tostring] != $record.notes)]
' temp/filtered.json > temp/changed.json
else
  cp temp/filtered8.json temp/changed.json
fi && \

jq '[.[] | select(.notes // "" | test("sha[dw]+ow|visit|\\bv[is]+t\\b|tour"; "i"))]' temp/changed.json > temp/filtered8v.json
```

### Step 4C: Filter with Claude (or Another AI Assistant)

```bash
jq '[.[] | {id, notes}]' temp/changed.json > temp/sanitized.json && \

claude --model sonnet --permission-mode auto \
"From temp/sanitized.json, return data in which the id is visiting, touring, or shadow visiting a school for high school admissions purposes. Exclude data where 'visit', 'tour', 'shadow', or common misspellings of such refer to something else — such as visiting family, doctor visits, sports tournaments, or other non-school-search activities. Also exclude data where id is accompanying a sibling to their high school visit, tour, or shadow visit rather than doing their own school search. If data is ambiguous, then include the data anyway. Double check if any data is missing. Output only the raw JSON array." > temp/filtered_ai.json && \

sed -n '/^\[/,/^\]$/p' temp/filtered_ai.json > temp/filtered_clean.json && \
mv temp/filtered_clean.json temp/filtered_ai.json
```

### Step 4D: Output or Update Results

```bash
if [ -f output.json ]; then
  jq --slurpfile changed temp/changed.json '
  ($changed[0] | map({key: (.id | tostring), value: .}) | from_entries) as $changes |
  [.[] | if $changes[.id | tostring] then $changes[.id | tostring] else . end]
' output.json > temp/output_updated.json && \

  mv temp/output_updated.json output.json
else
  jq --slurpfile lookup temp/filtered_ai.json '
    ($lookup[0] | map(.id)) as $ids |
    [.[] | select(.id | IN($ids[]))]
  ' temp/filtered.json > output.json 
fi && \

rm -rf temp/
```

The commands will store your credentials and make them available, retrieve and store your access token, create a script and make it executable, and cleanly, sensitively, thoroughly, and efficiently run the query and output results. Your credentials do not expire, but your access code _does_. Data processed in AI is sanitized, so feel free to utilize an alternative AI assistant.

Here on, you can simply re-retrieve and store your access token (Step 2) and cleanly re-run the query and output results (Steps 4A-4D). You do not need to re-set the credentials (Step 1) and re-create the script (Step 3).

You can view query progress by opening the temp/ folder. See `output.json` for query results; optionally, you can make the results more readable (see "Format JSON Response like Veracross UI Response").

## Background

### Running Query Using Veracross UI

To achieve a similar result in the UI, go to the LaunchPad > Daily Logistics > Attendance > General > Find Daily Attendance.

Click on the Query tab...<br>
Visualization: Data Grid

Click on the Fields tab...<br>
Add **Attendance Date** is on or after `09/01/25`<br>
Add **Person**

~~Add **PERSON: Grade Level Enrolled At** in `Grade 8`<br>~~
~~> PERSON: Grade Level Enrolled At has a One-To-Many Relationship because some students are in multiple preschool levels. (Not an issue for Grade 8.)~~ PERSON: Grade Level Enrolled At is _not_ necessarily student's current grade level

Add **PERSON: Current Grade** contains exactly (Grade 8)<br>
Add **Notes** contains "shadow," or "visit," or "tour"
Add **Attendance Category**<br>
Add **Late Arrival Time**<br>
Add **Early Dismissal Time**<br>

> For Notes, input criteria value: `shadow; visit; tour`. Every school visit/tour entry contains at least one of these three words. (I would also include common misspellings.)

Ascending order by Attendance Date, then ascending order by Person<br>
You can hide the PERSON: Current Grade field

Unfortunately, in the UI there is no other way to filter entries more. Many remaining entries are not school visits/tours (e.g., student visits family, participates in a tournament, or accompanies a sibling to their high school visit, tour, or shadow visit rather than doing their own school search). We need more granularity!

### Running Query Using Veracross API (macOS)

Veracross UI does not permit using an SQL-like query. So, we will need to use its API and process data locally. The API requires three credentials: `school_route`, `client_id`, and `client_secret`

#### Retrieve Credentials

School route:<br>
`school_route={subdirectory}`

Example: "cais" (sans quotes) in https://axiom.veracross.com/cais/

Client ID and Secret:<br>
`client_id={your_client_id}`<br>
`client_secret={your_client_secret}`

To obtain the client ID and secret, a user with a OAuth_App_Admin supplemental security role must create an internal integration in Identity & Access Management

#### Enable Scopes

Attendance Date, Person, Notes, Attendance Category, Late Arrival Time, and Early Dismissal Time parameters are located at (i.e., exposed by) endpoint `master_attendance`. PERSON: Current Grade parameter is located at endpoint `directory/student`.

In your newly created OAuth application, enable two scopes: `master_attendance:list` and `directory.student:list`. We will request the scopes with an access token next, so we can access the endpoints.

#### Retrieve Access Token

In a terminal emulator (e.g., macOS Terminal), run the command:

```bash
export access_token=$(curl --silent --request POST https://accounts.veracross.com/{subdirectory}/oauth/token \
  --data "grant_type=client_credentials" \
  --data "client_id={your_client_id}" \
  --data "client_secret={your_client_secret}" \
  --data "scope=master_attendance:list directory.student:list" | jq --raw-output '.access_token')
```

Replace `{subdirectory}`, `{your_client_id}`, and `{your_client_secret}` with the credential values you retrieved earlier. The command will retrieve an access token and store is value in variable: `access_token`. Used tokens expire in 1 hour, so _re-run this command after each token expires_.

#### Run Query

##### Retrieve All Attendance Records

Attendance Date, Person, Notes, Attendance Category, Late Arrival Time, Early Dismissal Time, etc.

Create a shell script, for example `fetch_attendance.sh`:

```bash
date=$(date -j -v+$1d -f "%Y-%m-%d" "2025-09-01" +%Y-%m-%d); \
sleep 0.5; \
curl --silent --get "https://api.veracross.com/{subdirectory}/v3/master_attendance" \
  --header "Authorization: Bearer {your_access_token}" \
  --header "X-Page-Size: 1000" \
  --data-urlencode "attendance_date=$date" > $1-attendance.json
```

Make the script executable: `chmod +x fetch_attendance.sh`<br>
Alternatively: `chmod 755 fetch_attendance.sh` (same result)

Then, run the script with this command:
```bash
seq 0 283 | xargs --max-procs=2 -I N bash ./fetch_attendance.sh N
```

The bash command will run 284 times (0, 1, 2, 3, ..., 283), in order to generate attendance records for Sep 1, Sep 2, Sep 3, ..., Jun 10/11 (`0-attendance.json`, `1-attendance.json`, `2-attendance.json`, `3-attendance.json`, ..., `283-attendance.json`). These attendance records are of _all_ students, not just of eighth grade students.

The command will also run at most two cycles at a time (`--max-procs=2`) with a half-second pause between each cycle (`sleep 0.5`), together to speed up processing and not trigger rate limits. (Rate limit is 300 requests every 3 minutes, meaning the speed limit is ~1.67 requests per second; 284 requests < 300, and our speed ~0.8–2 requests per second per my discussion with Claude. A greater number of parallel processes, less sleep, splitting up parallel processes, and/or clever workarounds could work to accelerate requests, but you risk hitting the rate limit or violating terms of service.)

`xargs` commands must be short, otherwise the terminal emulator will complain: `xargs: command line cannot be assembled, too long`. This is why we created the script file, instead of placing the script contents in the `xargs` command.

##### Retrieve Grade 8 Student Records

PERSON: Current Grade et al.

```bash
curl --silent --get "https://api.veracross.com/{subdirectory}/v3/directory/student" \
  --header "Authorization: Bearer {your_access_token}" \
  --header "X-Page-Size: 1000" \
  --data-urlencode "grade_level=8" > grade8.json
```

##### Process Data Locally

Filter attendance records for students in grade 8.

```bash
jq --slurp --slurpfile names grade8.json '
  ($names[0].data | map(.student_id) | map(tostring)) as $ids |
  [.[].data // [] | .[] | select(.person_id | tostring | IN($ids[]))] |
  sort_by(.attendance_date, .person)
' *-attendance.json > filtered8.json
```

You might ask: Why generate multiple temporary JSON files and then combine them into `filtered8.json`? The answer to that question is: Otherwise, the parallel processes corrupted `filtered8.json`


Next, filter for notes containing "shadow," or "visit," or "tour."

```bash
jq --slurp '[.[] | .[] | select(.notes // "" | test("shadow|visit|tour"; "i"))]' filtered8.json > filtered8v.json
```

Entries in `filtered8v.json` will be identical to entries in the Veracross UI, again had you run the query using the UI instead of the API; however, the API returns entries in JSON format, along with additional fields. 

We will make the entries more readable and tidy up the fields, later. For now, it is important to achieve more granularity so that all remaining entries are school visits/tours.








jq --slurp '[.[].data // [] | .[] | select(.notes // "" | test("sha[dw]+ow|visit|\\bv[is]+t\\b|tour"; "i"))] | sort_by(.attendance_date, .person)' *.json > filtered8.json
```
Be patient! You will retrieve a JSON response in a moment, and you can review it in the `output.json` file. (You can also output the response directly in the terminal emulator, however JSON responses can be exceptionally long.)

> In the shell script, I have also replaced `N` with `$1`, so that `xargs` passes the value of `N` (0, 1, 2, ..., 289) into the script as argument `$1`. (Any additional arguments must be `$2`, `$3`, `$4`, etc.)<p>
> The second `N` after `fetch_attendance.sh` in the `xargs` command is what changes value and is what is passed into the script. The first `N` after `-I` defines the placeholder name, so just make sure to match the placeholders.<p>
> `sha[dw]+ow|visit|\\bv[is]+t\\b|tour` is a regular expression that will catch common misspellings of "shadow" and "visit" (e.g., _shawdow_ and _vist_). Word boundary anchors, `\\b`, effectively exclude correct spellings that are unrelated (e.g., _cavity_ and _activist_). "Tour" is not misspelled commonly.

##### Utilize Claude (or Another AI Assistant) to Filter More

Not all visits/tours are to schools, however, so we must refine the query results more.

~~Extract `id` and `person` data from `filtered.json`, and keep the data associated: (we will use the extracted JSON file as a lookup table)~~ REDUNDANT

~~```bash~~
~~jq '[.[] | {id, person}]' filtered.json > lookup.json~~
~~```~~

~~Sanitize `filtered.json` by deleting `person` data:~~ INEFFICIENT

~~```bash~~
~~jq '[.[] | del(.person)]' filtered.json > sanitized.json~~
~~```~~

Extract `id` and `notes` data from `filtered.json`: (do not use `person_id`, since it repeats)

```bash
jq '[.[] | {id, notes}]' filtered.json > sanitized.json
```

Prompt Claude (or another AI assistant) to extract `id` and `notes` data from `sanitized.json` of any students who are likely visiting schools, touring schools, or shadow visiting:

```bash
claude --model sonnet --permission-mode auto \
"From sanitized.json, return data in which the id is visiting, touring, or shadow visiting a school for high school admissions purposes. Exclude data where 'visit', 'tour', 'shadow', or common misspellings of such refer to something else — such as visiting family, doctor visits, sports tournaments, or other non-school-search activities. Also exclude data where id is accompanying a sibling to their high school visit, tour, or shadow visit rather than doing their own school search. If data is ambiguous, then include the data anyway. Double check if any data is missing. Output only the raw JSON array." > filtered_ai.json
```
> Haiku model is too aggressive at excluding data, and Sonnet model may miss data on the first pass. In fact, extracting `id` and `notes` data for the prompt, not only saves AI tokens and — thus — lowers the chance of hitting rate limits, but also mitigates the risk of AI excluding data. (We also saved AI tokens by not relying on Claude \[or another AI assistant\] to filter for "shadow," "visit," "tour," and common misspellings, since we did not need to rely on it.) Auto permission mode allows Claude to make its own decisions based on its internal safety model. Requesting Claude to make a triple check produced identical content.

Wait for a moment! For me, it took about 3-4 minutes to complete ~~on a MacBook Air M1~~ LOCAL HARDWARE IS IRRELEVANT

Sometimes, Claude may format the JSON array incorrectly, even if you additionally prompt it to start the array with `[` and end it with `]`, and even if you additionally prompt it: `"...No preamble, no explanation, no markdown, no code fences."` So, I would run an extra command to ensure that the array is formatted correctly:

```bash
sed -n '/^\[/,/^\]$/p' temp/filtered_ai.json > temp/filtered_clean.json && \
mv temp/filtered_clean.json temp/filtered_ai.json
```

Afterward, trim `filtered.json`:

```bash
jq --slurpfile lookup filtered_ai.json '
  ($lookup[0] | map(.id)) as $ids |
  [.[] | select(.id | IN($ids[]))]
' filtered.json > output.json
```

##### Optimize API Query More

###### Confine Date Range

Since only data for current and upcoming visits, tours, and shadow visits are useful, we can confine the date range more.

```bash
start="2025-09-01" # default
today=$(date +%Y-%m-%d)
end="2026-06-11" # default

today=$(( ($(date -j -f "%Y-%m-%d" "$today" +%s) - $(date -j -f "%Y-%m-%d" "$start" +%s)) / 86400 ))
end=$(( ($(date -j -f "%Y-%m-%d" "$end" +%s) - $(date -j -f "%Y-%m-%d" "$start" +%s)) / 86400 ))

seq $today $end | xargs --max-procs=2 -I N bash ./fetch_attendance.sh N
```

###### Only Utilize Claude (or Another AI Assistant) to Filter Modified Notes

Extract `id` and `notes` data from `output.json`:

```bash
jq 'map({key: (.id | tostring), value: .notes}) | from_entries' output.json > temp/reference.json
```
Only keep data where notes changed:

```bash
jq --slurpfile old temp/reference.json '
  [.[] | . as $record | select($old[0][$record.id | tostring] != null and $old[0][$record.id | tostring] != $record.notes)]
' temp/filtered.json > temp/changed.json
```

Extract `id` and `notes` data from `changed.json`, instead of from `filtered.json`:

```bash
jq '[.[] | {id, notes}]' temp/changed.json > temp/sanitized.json
```

Prompt Claude (or another AI assistant), then update `output.json`: (could also have split up commands like above)

```bash
jq --slurpfile changed temp/changed.json '
  ($changed[0] | map({key: (.id | tostring), value: .}) | from_entries) as $changes |
  [.[] | if $changes[.id | tostring] then $changes[.id | tostring] else . end]
' output.json > temp/output_updated.json && \

mv temp/output_updated.json output.json
```

We would just need to check that `output.json` exists, and add `-p` option to `mkdir temp/` command in case the folder already exists.

If you choose another AI assistant, do not choose the assistant if it is just because it is faster. Test its results against what you would get using my Claude Sonnet prompt. Not that, say, ChatGPT or Gemini would not work, but I did not test them.

##### Empty API Responses

If the JSON response is empty (i.e., `[]`), either the query found nothing or the access token has expired. To check if the access token has expired, run the command:

```bash
curl --silent --request GET \
  --url "https://api.veracross.com/{subdirectory}/v3/master_attendance" \
  --header "Authorization: Bearer {your_access_token}" | jq .error
```

It will return either `"The provided access token has expired"` or, if not expired, `null`. 

Again, query requests are also subject to rate limits of 300 requests every 3 minutes, also meaning a request speed limit of ~1.67 requests per second.

##### Data Workflow

Essentially, we retrieve student records dated Sep 1 to mid-Jun, and then we filter them: first with a regular expression, and then with an AI assistant.

```bash
curl: *.json 
      |
[sha[dw]+ow|visit|\\bv[is]+t\\b|tour]
      |
      v
filtered.json
      |
[new/changed]
      |
      v
      |-- {id,notes} -> sanitized.json
      |                      |
      |                [AI assistant]
    {all}                    |
      |                      v
      |               filtered_ai.json
      |                      |
      +----> {id match} <----+
                  |
                  v
             output.json
```

What remains is only student records that reference visiting or revising, touring, or shadow visiting a high school for admissions.

No student records that reference visiting grandparents, family, or siblings. No records referencing doctor, dentist, wellness, or emergency room visits. No sports tournaments (e.g., fencing, golf, soccer, and volleyball). No passport appointments. No records in which a student accompanies a sibling to their high school visit, tour, or shadow visit rather than doing their own school search. No shadow visits to another K-8 school, and no traveling abroad.

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
5. If any notes in `output.json` contain Windows carriage returns with escape sequences, `\r\n`, or UNIX escape sequences, `\n`, keep them; this way, if you POST the notes to Veracross then its UI will display the field correctly.

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
  (.[] | [(.attendance_date | format_date), .person, (.attendance_category | format_category), (.late_arrival_time | format_time), (.early_dismissal_time | format_time), (.notes | gsub("\r\n"; "<br>") | gsub("\n"; "<br>"))])
  | @tsv' output.json \
  | sed 's/^/|/' \
  | sed 's/\t/|/g' \
  | sed 's/$/|/' > output.md
```

Open `output.md`

`jq` is a command-line tool for parsing, filtering, and transforming JSON, and `@tsv` is a jq formatter. `jq` extracts arrays from `output.json`, and `@tsv` converts them into tab separated strings.

`sed` is a command-line tool that reads text line by line and applies additional transformations; its basic syntax is `sed 's/find/replace/g'`. `^` means start of line; `\t` means tab character; and `$` means end of line.

# Note

I did try to optimize the query by using `last_modified_date`, but the parameter seems to have no usefulness (e.g., one record has `attendance_date` = `09/19/25` and `last_modified_date` = `02/02/26`). Even if the parameter were useful, almost 2,000 records exist with `last_modified_date` = "02/02/26" — possibly due to a system migration, data import, or administrative update, which would exceed the maximum `X-Page-Size` = 1000 (i.e., no greater than 1,000 records can be called at once). We could still use it, perhaps by splitting up calls, but I do not feel as though `last_modified_date` is as reliable as `attendance_date`.

# References

- [Veracross Axiom Help](https://community.veracross.com/s/) (API Overview, OAuth app setup and IAM configuration in the UI)
- [Veracross API Documentation](https://api-docs.veracross.com/) (e.g., endpoints, parameters, headers, and rate limits)
- [Claude Code command-line interface](https://code.claude.com/docs/en/cli-reference) (commands and flags)
- Unix/Linux command manuals: `man curl`, `man jq`, `man sed`, `man echo`, `man export`, `man grep`, `man xargs`, `man cat`, `man date`, `man sleep`, `man chmod`, `man mkdir`, `man seq`, `man bash`, `man rm`, and `man date` (e.g., syntax, options, and usage)