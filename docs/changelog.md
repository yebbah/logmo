# logmo: Change log by build

Each push to `main` gets a new build number (`CURRENT_PROJECT_VERSION` in `project.yml`); the version (`MARKETING_VERSION`) stays 1.0.0 until a release is named. The build shows in Settings → About as "Version 1.0.0 (4)". The PRD version each build was made to is given next to it.

## Build 4 (version 1.0.0), PRD v21.1, 27 November 2026

**Changed**
- **Measurements are always taken at the start and the end.** With measurements on, one is due on the campaign's first day (the baseline) and one in its last week (the end state), whatever the cadence (Weekly, Biweekly or Monthly) in between.
- **Progress photos.** The campaign setting is now "Measurements and photos". Turn on "Ask about progress photos on those days" and the Log screen asks "Have you taken your progress photos?" on the same days; Still to log says Progress photos due until you answer yes. Only the yes is recorded (in the backup and the CSV's `progress_photos` column); the photos stay in your Photos app.
- **Still to log** no longer shows the colour legend.

**Documentation**
- PRD v21.1 (FR-27 updated, decisions D147 to D149); user guide, release notes and production guide updated.

## Build 3 (version 1.0.0), PRD v21.0, 27 November 2026

**New**
- **Body measurements.** Waist at the navel, 2 in below and 2 in above it, chest, thighs, calves and biceps, typed in cm. Each campaign sets how often (Off, Weekly, Biweekly, Monthly = every four weeks) at setup. On a due day the Log screen opens a Measurements section and Still to log shows "Measurements due"; any other day you can add one from "Add measurements". The Dashboard and a campaign's detailed view chart a line per site (as change from the first reading) with switches per line and a table of the latest reading and change. Included in the CSV export (`measure_<site>_cm`) and the full backup.
- **Two paces in the weekly suggestion.** A Conservative and an Aggressive option side by side, each with its calories and the weight change it points to. Settings → Weekly suggestion → Preferred pace decides which is selected first and which Apple Intelligence writes about. Aggressive is offered only with a maintenance estimate and reliable data, and not when illness, strained recovery or high hunger argue against it; it moves up to 250 kcal a day from the current goal inside the existing safety floor.
- **A plain-language Why** for every suggestion (progress for the campaign, distance to the target weight, whether you followed the plan, what the chosen pace means, what the measurements say, recovery), with the calculated numbers one tap away. Measurements inform the Why and the model's facts but never move a goal.

**Changed**
- **Still to log** has three colours for daily trackers: green (done, goal reached), amber (started, not complete or goal not reached yet), grey (nothing).
- **Dashboard order and content.** The campaign card under Showing is removed for running and finished campaigns (the week line and the days-left badge already say it) and the target weight, with the trend now and the distance from it, is in Recent performance. Estimated maintenance follows Recent performance. The Weekly rate of change is a bar graph (one bar per week, the current week paler, N/A gaps) straight after the weigh-ins chart.

**Documentation**
- PRD v21.0 (FR-27 Body measurements, decisions D141 to D146); user guide, release notes and production guide updated.

## Build 2 (version 1.0.0), PRD v20.9, 25 November 2026

**Changed**
- **One rate-of-change view.** The Dashboard keeps the Weekly rate of change table; the daily "Rate of change per week" bar chart is removed.
- **The weekly plan keeps each week's history.** Every week that has begun shows its weight trend at the end of the week and its change from the week before (kg and %, "N/A" when there is nothing earlier or the trend restarted, "so far" for the current week). This appears in the Weekly plan screen and in a campaign's detailed view.
- **Protein goal days moved.** The protein ring is gone from the Dashboard's weigh-ins card. Each plan week shows "Protein goal reached 4 of 6 days" instead (today is left out until the goal is reached).
- **Days-left badge** sits at the right end of the Dashboard's week line, so it adds no empty space above the title.
- **Maintenance card** shows the goal against maintenance as one line; the duplicated Goal and Eaten tiles are gone (the weekly table keeps them).

**Fixed**
- **Rate of change after a campaign starts or restarts the trend.** A change measured across a restart of the trend (a campaign's starting weight more than 0.3 kg from the old trend) is shown as "N/A" instead of a false jump, in the weekly table, the 7/14/21-day changes and the campaign look-back.
- **"Repeat for the weeks after"** now replaces weeks you had already set or confirmed (before, they were skipped without a word), and the editor says how many weeks it will replace.

**Documentation**
- PRD v20.2 to v20.9; user guide, release notes and production guide updated; this change log added.

## Build 1 (version 1.0.0), PRD up to v20.1, November 2026

The first build, installed on the owner's iPhone. It includes everything in the release notes up to PRD v20.1: logging, campaigns with weekly goals and the weekly plan, streaks, weight trend, Apple Health import (read only), Apple Intelligence weekly suggestions, estimated maintenance, reminders, backup and export, and explicit campaigns with a start and an end (no automatic or open-ended campaign).
