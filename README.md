# Running Veracross Query Using API, and Tracking Sign-Ups

Say we want to query every 8th grade student who is either visiting or touring a high school or is shadowing a high school student, as well track who has and has not signed up to do so.

## TL;DR

Feel free to either follow Steps 1-8 below, or customize, make executable and run [script.sh](script.sh)

### Step 1: Set Credentials

Retrieve your credentials (see "Retrieve Credentials"), and then in a terminal emulator (e.g., macOS Terminal) run these commands:

```bash
grep --quiet "^school_route=" .env || \
  echo "school_route={subdirectory}" >> .env && \
grep --quiet "^client_id=" .env || \
  echo "client_id={your_client_id}" >> .env && \
grep --quiet "^client_secret=" .env || \
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
EOF
chmod +x fetch_attendance.sh
```

### Step 4: Retrieve Student Records

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

### Step 5: Filter the Student Records

...And focus on records that have changed:

```bash
jq --slurp --slurpfile names temp/grade8.json '
  ($names[0].data | map(.student_id) | map(tostring)) as $ids |
  [.[].data // [] | .[] | select(.person_id | tostring | IN($ids[]))] |
  sort_by(.attendance_date, .person)
' temp/*-attendance.json > temp/filtered8.json && \

if [ -f output.json ]; then
  jq --slurpfile existing output.json '
    ($existing[0] | map({key: (.id | tostring), value: .notes}) | from_entries) as $old_notes |
    [.[] | . as $record | select(
      ($old_notes[$record.id | tostring] != null or $record.notes != null) and
      $old_notes[$record.id | tostring] != $record.notes
    )]
  ' temp/filtered8.json > temp/changed.json
else
  cp temp/filtered8.json temp/changed.json
fi
```

### Step 6: Filter with Regular Expression


```bash
jq '[.[] | select(.notes // "" | test("sha[dw]+ow|visit|\\bv[is]+t\\b|tour"; "i"))]' temp/changed.json > temp/filtered8v.json
```

### Step 7: Filter with Claude (or Another AI Assistant)

```bash
jq '[.[] | {id, notes}]' temp/filtered8v.json > temp/sanitized.json && \

while true; do
  claude --model sonnet --permission-mode auto \
  "From temp/sanitized.json, return data in which the id is visiting, touring, or shadow visiting a school for high school admissions purposes. Exclude data where 'visit', 'tour', 'shadow', or common misspellings of such refer to something else — such as visiting family, doctor visits, sports tournaments, or other non-school-search activities. Also exclude data where id is accompanying a sibling to their high school visit, tour, or shadow visit rather than doing their own school search. If data is ambiguous, then include the data anyway. Double check if any data is missing. Output only the raw JSON array." > temp/filtered8v_ai.json
  if [ -s temp/filtered8v_ai.json ]; then
    break
  fi
done && \

sed '/^```/d' temp/filtered8v_ai.json | \
sed -n '/^\[/,/^\]$/p' > temp/filtered8v_ai_clean.json && \
mv temp/filtered8v_ai_clean.json temp/filtered8v_ai.json
```

### Step 8: Output or Update Results, and Track Sign-Ups

```bash
if [ -f output.json ]; then
  jq --slurpfile changed temp/changed.json '
    ($changed[0] | map({key: (.id | tostring), value: .}) | from_entries) as $changes |
    (map(.id) | map(tostring)) as $existing_ids |
    ([.[] | if $changes[.id | tostring] then $changes[.id | tostring] else . end] +
    [$changed[0][] | select(.id | tostring | IN($existing_ids[]) | not)]) |
    sort_by(.attendance_date, .person)
  ' output.json > temp/output_updated.json && \
  mv temp/output_updated.json output.json
else
  cp temp/changed.json output.json
fi && \

if [ -f signups.json ]; then
  jq --slurpfile new temp/filtered8v_ai.json '
    ($new[0] | map(.id)) as $new_ids |
    [.[] | select(.id | IN($new_ids[]) | not)] + $new[0] |
    unique_by(.id)
  ' signups.json > temp/signups_merged.json && \
  mv temp/signups_merged.json signups.json
else
  cp temp/filtered8v_ai.json signups.json
fi && \

rm -rf temp/ && \
rm fetch_attendance.sh
```

The commands will store your credentials and make them available, retrieve and store your access token and make it available, create a script and make it executable, and cleanly, sensitively, thoroughly, and efficiently run the query, output results, and track sign-ups. Your credentials do not expire, but your access code _does_. Data processed in AI is sanitized, so feel free to utilize an alternative AI assistant.

You can view query progress by opening the temp/ folder. See `output.json` for query results and `signups.json` for sign-ups; then, see "Format JSON Response like Veracross UI Response with Sign-Up Tracking" to make the results more readable and formatted alongside sign-ups.

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
Add **Notes** contains "shadow," or "visit," or "tour"<br>
Add **Attendance Category**<br>
Add **Late Arrival Time**<br>
Add **Early Dismissal Time**<br>

> For Notes, input criteria value: `shadow; visit; tour`. Every school visit/tour entry contains at least one of these three words. (I would also include common misspellings.)

Ascending order by Attendance Date, then ascending order by Person<br>
You can hide the PERSON: Current Grade field

Unfortunately, in the UI there is no other way to filter entries more or track sign-ups easily. Many remaining entries are not school visits/tours (e.g., student visits family, participates in a tournament, or accompanies a sibling to their high school visit, tour, or shadow visit rather than doing their own school search). We need more granularity!

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

Remember: These attendance records are of _all_ students, not just of eighth grade students.

The bash command will run 284 times (0, 1, 2, 3, ..., 283), in order to generate attendance records for Sep 1, Sep 2, Sep 3, ..., Jun 10/11 (`0-attendance.json`, `1-attendance.json`, `2-attendance.json`, `3-attendance.json`, ..., `283-attendance.json`). `xargs` passes the value of `N` (0, 1, 2, 3, ..., 283) into the script as argument `$1`. (More specifically, the second `N` after `fetch_attendance.sh` is what changes value and is what is passed into the script. The first `N` after `-I` defines the placeholder name, so just make sure to match the placeholders. Any additional arguments in the script must be `$2`, `$3`, `$4`, etc.) 

The command will also run at most two cycles at a time (`--max-procs=2`) with a half-second pause between each cycle (`sleep 0.5`) to speed up processing and not trigger rate limits. (Rate limit is 300 requests every 3 minutes, meaning the speed limit is ~1.67 requests per second; 284 requests < 300, and our speed ~0.8–2 requests per second per my discussion with Claude. A greater number of parallel processes, less sleep, splitting up parallel processes, and/or clever workarounds could work to accelerate requests, but you risk hitting the rate limit or violating terms of service.)

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

All the records will initially be wrapped with metadata: `{"data":` and `}`, so the command will also strip it out. `person_id` in `0-attendance.json`, `1-attendance.json`, `2-attendance.json`, `3-attendance.json`, etc. is equivalent to `student_id` in `grade8.json`. So, we are filtering by keeping data records in each attendance file in which `person_id`=`student_id`. "*" in `*-attendance.json` will make the command parse all the attendance files.

You might ask: Why generate multiple temporary JSON files and then combine them into `filtered8.json`? The answer to that question is: Otherwise, the parallel processes corrupted `filtered8.json`

Next, filter for notes containing "shadow," or "visit," or "tour."

```bash
jq '[.[] | select(.notes // "" | test("shadow|visit|tour"; "i"))]' filtered8.json > filtered8v.json
```

Entries in `filtered8v.json` will be identical to entries in the Veracross UI, again had you run the query using the UI instead of the API; however, the API returns entries in JSON format, along with additional fields (e.g., `id` which we will use coming up, and `person_id`). (You can also output commands directly in the terminal emulator, however JSON responses can be exceptionally long.)

We will track sign-ups, make the entries more readable, and tidy up the fields, later. For now, it is important to achieve more granularity so that all remaining entries are school visits/tours.

##### More Granularity

###### Regular Expression

Filter for notes containing "shadow," or "visit," or "tour," _or_ any common misspellings of each.

```bash
jq '[.[] | select(.notes // "" | test("sha[dw]+ow|visit|\\bv[is]+t\\b|tour"; "i"))]' filtered8.json > filtered8v.json
```

`sha[dw]+ow|visit|\\bv[is]+t\\b|tour` is a regular expression that will catch misspellings of "shadow" and "visit" (e.g., _shawdow_ and _vist_). The regular expression also goes a step further by excluding misspellings of "visit" that are unrelated (e.g., _cavity_ and _activist_); notice the word boundary anchors, `\\b`. ("Tour" is not misspelled commonly.)

###### Claude (or Another AI Assistant)

Extract `id` and `notes` data from `filtered8v.json`: (`id` is a student's attendance ID, which is unique, so do not use `person_id` which repeats)

```bash
jq '[.[] | {id, notes}]' filtered8v.json > sanitized.json
```

Prompt Claude (or another AI assistant) to extract `id` and `notes` data from `sanitized.json` of any students who are likely visiting schools, touring schools, or shadow visiting: (you can look at `id` as a student's ID for a particular day)

```bash
while true; do
  claude --model sonnet --permission-mode auto \
  "From sanitized.json, return data in which the id is visiting, touring, or shadow visiting a school for high school admissions purposes. Exclude data where 'visit', 'tour', 'shadow', or common misspellings of such refer to something else — such as visiting family, doctor visits, sports tournaments, or other non-school-search activities. Also exclude data where id is accompanying a sibling to their high school visit, tour, or shadow visit rather than doing their own school search. If data is ambiguous, then include the data anyway. Double check if any data is missing. Output only the raw JSON array." > filtered8v_ai.json
  if [ -s filtered8v_ai.json ]; then
    break
  fi
done
```

Wait for a moment! For a full school year's worth of data, Claude responded in about 3-4 minutes ~~on a MacBook Air M1~~ LOCAL HARDWARE IS IRRELEVANT, SPEED RELIES ON ANTHROPIC SERVERS. The command will also check if the AI assistant's response is empty because on rare occasions it is; just make sure that you are checking the correct file and location, otherwise the WHILE loop will keep looping, and you will hit a rate limit.

Haiku model is too aggressive at excluding data, and the Sonnet model may miss data on the first pass. In fact, extracting `id` and `notes` data for the prompt, not only saves AI tokens and — thus — accelerates response times and lowers the chance of hitting rate limits, but also mitigates the risk of AI excluding data. (We also saved AI tokens by not relying on Claude \[or another AI assistant\] to filter for "shadow," "visit," "tour," and common misspellings, since we did not need to rely on it.) Auto permission mode allows Claude to make its own decisions based on its internal safety model. (Requesting Claude to make a triple check produced identical content.)

Sometimes, not will Claude produce an empty response, but also Claude may format the JSON array incorrectly — even if you additionally prompt it to start the array with `[` and end it with `]`, and even if you additionally prompt it: `"...No preamble, no explanation, no markdown, no code fences."` So, I would run an extra command to ensure that the array is formatted correctly:

```bash
sed '/^```/d' temp/filtered8v_ai.json | \
sed -n '/^\[/,/^\]$/p' > temp/filtered8v_ai_clean.json && \
mv temp/filtered8v_ai_clean.json temp/filtered8v_ai.json
```

##### Generate Output

Keep data in `filtered8v.json` for `id` in `filtered8v_ai.json`

```bash
jq --slurpfile lookup filtered8v_ai.json '
  ($lookup[0] | map(.id)) as $ids |
  [.[] | select(.id | IN($ids[]))]
' filtered8v.json > output.json
```

Entries in `output.json` will be more refined than entries in the Veracross UI; however, again the API returns entries in JSON format, along with additional fields (e.g., `id` which we used to sanitize the data).

#### Optimize API Query More

Utilizing parallel processing, half-second pauses, data sanitization, the proper AI model, and only the AI model when you need it all helped optimize commands above. We can optimize the commands even more. 

##### Alternative Method to Speed Up Processing Attendance

Since only data records for current and upcoming visits, tours, and shadow visits are useful, we can confine the date range more.

```bash
start="2025-09-01" # default
today=$(date +%Y-%m-%d)
end="2026-06-11" # default

today=$(( ($(date -j -f "%Y-%m-%d" "$today" +%s) - $(date -j -f "%Y-%m-%d" "$start" +%s)) / 86400 )) # converts today's date to number of days since start date
end=$(( ($(date -j -f "%Y-%m-%d" "$end" +%s) - $(date -j -f "%Y-%m-%d" "$start" +%s)) / 86400 )) # converts end date to number of days since start date

seq $today $end | xargs --max-procs=2 -I N bash ./fetch_attendance.sh N # replace "0" and "283"
```

Just make sure to strip the comments after `#` before running the command.

###### Only Filter Modified Notes

Right after you filter attendance records for students in grade 8...

Use `output.json` as a reference file. If it exists (which it would, in this case), extract data records of which notes have changed. It it does not exist, essentially all records have changed. Of course, since we filter many records to generate `output.json`, then `changed.json` will also contain records we had already filtered out earlier.

```bash
if [ -f output.json ]; then
  jq --slurpfile existing output.json '
    ($existing[0] | map({key: (.id | tostring), value: .notes}) | from_entries) as $old_notes |
    [.[] | . as $record | select(
      ($old_notes[$record.id | tostring] != null or $record.notes != null) and
      $old_notes[$record.id | tostring] != $record.notes
    )]
  ' filtered8.json > changed.json
else
  cp filtered8.json changed.json
fi
```

Filter changed data with the regular expression and Claude (or another AI assistant).

```bash
jq '[.[] | select(.notes // "" | test("sha[dw]+ow|visit|\\bv[is]+t\\b|tour"; "i"))]' changed.json > filtered8v.json # changed filtered8.json to changed.json

# keep the sanitize command, Claude prompt, and clean command as they are

jq --slurpfile lookup filtered8v_ai.json '
  ($lookup[0] | map(.id)) as $ids |
  [.[] | select(.id | IN($ids[]))]
' filtered8v.json > output_changed.json # changed output.json to output_changed.json
```

Again, just make sure to strip the comments after `#` before running the command.

(If you choose another AI assistant, though, do not choose the assistant if it is just because the assistant is faster. Test its responses against what you would receive using my Claude Sonnet prompt. Not that, say, ChatGPT or Gemini would not work, but I did not test them.)

Then, if `output.json` exists update its records. It it does not exist, essentially all its records are new.

```bash
if [ -f output.json ]; then
  jq --slurpfile changed output_changed.json '
    ($changed[0] | map({key: (.id | tostring), value: .}) | from_entries) as $changes |
    (map(.id) | map(tostring)) as $existing_ids |
    ([.[] | if $changes[.id | tostring] then $changes[.id | tostring] else . end] +
    [$changed[0][] | select(.id | tostring | IN($existing_ids[]) | not)]) |
    sort_by(.attendance_date, .person)
  ' output.json > output_updated.json && \
  mv output_updated.json output.json
else
  cp output_changed.json output.json
fi
```

The command also re-sorts the data records.

##### Suggestions

1. In each command, replace:<p>
`{subdirectory}` &rarr; `$school_route`<br>
`{your_client_id}` &rarr; `$client_id`<br>
`{your_client_secret}` &rarr; `$client_secret`<br>
`{your_access_token}` &rarr; `$access_token`
2. Either manually export the environment variables: `school_route`, `client_id` and `client_secret` with their values OR<p>
(And this is what I do) Place the environment variables and their values in a `.env` file, and export them by running: `export $(grep --invert-match '^#' .env | xargs)`
3. _Then_ run the command to retrieve the access token, and then run the API query.
4. Better yet, create a temporary folder: `mkdir -p temp/`, generate the multiple JSON files in there: `$1-attendance.json` &rarr; `temp/$1-attendance.json` (and, thus, `grade8.json` &rarr; `temp/grade8.json` and `*-attendance.json` &rarr; `temp/*-attendance.json`), in fact generate all working files in there, and once you complete your query clean up the temporary JSON files with `rm -rf temp/`
5. If any notes in `output.json` contain Windows carriage returns with escape sequences, `\r\n`, or UNIX escape sequences, `\n`, keep them; this way, if you update notes in the Veracross UI via the API, then its UI will display the field correctly.
> The command to retrieve the access token exports `access_token` environment variable and its value for you. So, do not export `access_token` and its value manually or place in `.env`

## Tracking Sign-Ups

Every 8th grade student who is either visiting or touring a high school or is shadowing a high school student has signed up to do so on certain days. So, let us add the `id` of students we have filtered to a sign up "sheet" named `signups.json`, unless it already exists in which case simply update it. (Again, `id` is a student's attendance ID, but you can look at it as a student's ID for a particular day.)


```bash
if [ -f signups.json ]; then
  jq --slurpfile new filtered8v_ai.json '
    ($new[0] | map(.id)) as $new_ids |
    [.[] | select(.id | IN($new_ids[]) | not)] + $new[0] |
    unique_by(.id)
  ' signups.json > signups_merged.json && \
  mv signups_merged.json signups.json
else
  cp filtered8v_ai.json signups.json
fi
```

Everyone who is neither visiting, nor touring, nor shadowing has not signed up. `output.json` does not currently display data records for these students, so we will need to relax the output.

Again, if `output.json` exists, update its records. It it does not exist, essentially all its records are new. However, change the reference file from `output_changed.json` to `changed.json`. Recall that `change.json` contains all changed entries before filtering them with the regular expression and the AI assistant.

```bash
if [ -f output.json ]; then
  # jq --slurpfile changed output_changed.json '
  jq --slurpfile changed changed.json '
    ($changed[0] | map({key: (.id | tostring), value: .}) | from_entries) as $changes |
    (map(.id) | map(tostring)) as $existing_ids |
    ([.[] | if $changes[.id | tostring] then $changes[.id | tostring] else . end] +
    [$changed[0][] | select(.id | tostring | IN($existing_ids[]) | not)]) |
    sort_by(.attendance_date, .person)
  ' output.json > output_updated.json && \
  mv output_updated.json output.json
else
  cp changed.json output.json # output_changed.json to changed.json
fi
```

Also changed in the command is we stripped out codes that would add any missing entries, since `output.json` will now include all students. In effect, we can also strip out one block of code earlier that generated `output_changed.json`

```bash
# jq --slurpfile lookup filtered8v_ai.json '
#   ($lookup[0] | map(.id)) as $ids |
#   [.[] | select(.id | IN($ids[]))]
# ' filtered8v.json > output_changed.json
```

Also in effect, since we no longer filter records to generate `output.json`, then `changed.json` will no longer contain records we had already filtered out.

##### Data Workflow and Result

Now that we have addressed how to run, and optimize, our query using the Veracross API, so that we can achieve more refined data record entries, let us summarize the workflow.

Essentially, we retrieve student records dated Sep 1 to mid-Jun, and then we filter them: first by grade, second with a regular expression, and third with an AI assistant. We focus on data records that have changed.

```bash
  curl: *-attendance.json
     curl: grade8.json
             |
{person_id=student_id only}
             |
             v
       filtered8.json
             |
         [changed]
             |
             |-- [sha[dw]+ow|visit|\\bv[is]+t\\b|tour]
             |                     |
             |                     v
             |              filtered8v.json
             |                     |
             |              {id,notes only}
             |                     |
           {all}                   v
             |               sanitized.json
             |                     |
             |               [AI assistant]
             |                     |
             |                     v
             |             filtered8v_ai.json
             |                     |
             v                     v
        output.json           signups.json
```

What remains is student records that reference visiting, touring, or shadow visiting a high school for admissions.

No student records that reference visiting grandparents, family, or siblings. No records referencing doctor, dentist, wellness, or emergency room visits. No sports tournaments (e.g., fencing, golf, soccer, and volleyball). No passport appointments. No records in which a student accompanies a sibling to their high school visit, tour, or shadow visit rather than doing their own school search. No shadow visits to another K-8 school, and no traveling abroad.

## Format JSON Response like Veracross UI Response with Sign-Up Tracking

Now, let us make the entries more readable and tidy up the fields.

We will extract Attendance Date, Person, Notes, Attendance Category, Late Arrival Time, and Early Dismissal Time data records from `output.json`, check if `id` in `signups.json` exist in `output.json`, and then export the data and finding into a markdown file. 

If students sign up, the command will place an "x" next to their name, for each day that they are visiting, touring, or shadow visiting. The command below also formats the attendance date, attendance category, and late arrival time and early dismissal time as the dates, categories and times are formatted in the UI.

Run the entire command:

```bash
jq --raw-output --slurpfile signups signups.json '
  ($signups[0] | map(.id) | map(tostring)) as $signup_ids |
  def format_date: 
    if . == null then ""
    else split("-") | .[1] + "/" + .[2] + "/" + (.[0][2:]) end;

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

  ["date","person","signed_up","notes","attendance_category","late_arrival_time","early_dismissal_time"],
  ["----","------","---------","-----","-------------------","----------------","--------------------"],
  (.[] | [(.attendance_date // "" | format_date), (.person // ""), (if (.id | tostring) | IN($signup_ids[]) then "x" else "" end), (.notes // "" | gsub("\r\n"; "<br>") | gsub("\n"; "<br>")), (.attendance_category | format_category), (.late_arrival_time | format_time), (.early_dismissal_time | format_time)])
  | @tsv' output.json \
  | sed 's/^/|/' \
  | sed 's/\t/|/g' \
  | sed 's/$/|/' > output.md
```

Open `output.md`

`jq` is a command-line tool for parsing, filtering, and transforming JSON, and `@tsv` is a jq formatter. `jq` extracts arrays from `output.json`, and `@tsv` converts them into tab separated strings.

`sed` is a command-line tool that reads text line by line and applies additional transformations; its basic syntax is `sed 's/find/replace/g'`. `^` means start of line; `\t` means tab character; `$` means end of line; and `g` means global.

# Note

I did try to optimize the query by using `last_modified_date`, but the parameter seems to have no usefulness (e.g., one record has `attendance_date` = `09/19/25` and `last_modified_date` = `02/02/26`). Even if the parameter were useful, almost 2,000 records exist with `last_modified_date` = "02/02/26" — possibly due to a system migration, data import, or administrative update, which would exceed the maximum `X-Page-Size` = 1000 (i.e., no greater than 1,000 records can be called at once). We could still use it, perhaps by splitting up calls, but I do not feel as though `last_modified_date` is as reliable as `attendance_date`.

# References

- [Veracross Axiom Help](https://community.veracross.com/) (API Overview, and OAuth app setup and IAM configuration in the UI)
- [Veracross API Documentation](https://api-docs.veracross.com/) (e.g., endpoints, parameters, headers, and rate limits)
- [Claude Code command-line interface](https://code.claude.com/docs/en/cli-reference) (commands and flags)
- Unix command manuals: `man curl`, `man jq`, `man sed`, `man echo`, `man export`, `man grep`, `man xargs`, `man cat`, `man date`, `man sleep`, `man chmod`, `man mkdir`, `man seq`, `man bash`, `man rm`, and `man date` (e.g., syntax, options, and usage)
