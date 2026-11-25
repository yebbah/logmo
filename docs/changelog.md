# logmo: Change log by build

Each push to `main` gets a new build number (`CURRENT_PROJECT_VERSION` in `project.yml`); the version (`MARKETING_VERSION`) stays 1.0.0 until a release is named. The build shows in Settings → About as "Version 1.0.0 (2)". The PRD version each build was made to is given next to it.

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
