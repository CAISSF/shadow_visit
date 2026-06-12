# !/bin/bash

# Step 1: Set Credentials
grep --quiet "^school_route=" .env || \
  echo "school_route={subdirectory}" >> .env && \
grep --quiet "^client_id=" .env || \
  echo "client_id={your_client_id}" >> .env && \
grep --quiet "^client_secret=" .env || \
  echo "client_secret={your_client_secret}" >> .env && \

export $(grep --invert-match '^#' .env | xargs) && \


# Step 2: Get Access Token (Expires in 1 Hour)
export access_token=$(curl --silent --request POST https://accounts.veracross.com/$school_route/oauth/token \
  --data "grant_type=client_credentials" \
  --data "client_id=$client_id" \
  --data "client_secret=$client_secret" \
  --data "scope=master_attendance:list directory.student:list" | jq --raw-output '.access_token') && \


# Step 3: Create a Script
cat > fetch_attendance.sh << 'EOF'
date=$(date -j -v+$1d -f "%Y-%m-%d" "2025-09-01" +%Y-%m-%d); \
sleep 0.5; \
curl --silent --get "https://api.veracross.com/$school_route/v3/master_attendance" \
  --header "Authorization: Bearer $access_token" \
  --header "X-Page-Size: 1000" \
  --data-urlencode "attendance_date=$date" > temp/$1-attendance.json
EOF
chmod +x fetch_attendance.sh && \


# Step 4: Retrieve Student Records
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
  --data-urlencode "grade_level=8" > temp/grade8.json && \


# Step 5: Filter the Student Records
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
fi && \


# Step 6: Filter with Regular Expression
jq '[.[] | select(.notes // "" | test("sha[dw]+ow|visit|\\bv[is]+t\\b|tour"; "i"))]' temp/changed.json > temp/filtered8v.json && \


# Step 7: Filter with Claude (or Another AI Assistant)
jq '[.[] | {id, notes}]' temp/filtered8v.json > temp/sanitized.json && \

while true; do
  claude --model sonnet --permission-mode auto \
  "From temp/sanitized.json, return data in which the id is visiting, touring, or shadow visiting a school for high school admissions purposes. Exclude data where 'visit', 'tour', 'shadow', or common misspellings of such refer to something else — such as visiting family, doctor visits, sports tournaments, or other non-school-search activities. Also exclude data where id is accompanying a sibling to their high school visit, tour, or shadow visit rather than doing their own school search. If data is ambiguous, then include the data anyway. Double check if any data is missing. Output only the raw JSON array." > temp/filtered8v_ai.json
  if [ -s temp/filtered8v_ai.json ]; then
    break
  fi
done && \

sed -n '/^\[/,/^\]$/p' temp/filtered8v_ai.json > temp/filtered8v_ai_clean.json && \
mv temp/filtered8v_ai_clean.json temp/filtered8v_ai.json && \


# Step 8: Output or Update Results, and Track Sign-Ups
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
