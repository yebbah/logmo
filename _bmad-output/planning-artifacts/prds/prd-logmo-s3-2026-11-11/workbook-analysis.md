# Sanitized workbook evidence — Athletic Foundation

## Scope and handling

Analyzed only the local `S3 - Athletic Foundation.xlsx` workbook. It was opened read-only; no cell values containing personal data, names, entered dates, measurements, or results are reproduced here. Evidence below is workbook structure, labels, formulas, references, validation rules, and chart ranges only.

The workbook contains 13 tabs. The exact analytics tab is **`AllDatHDE`** (not `AllDatDHE`). Visible tabs are `Data Input`, `AllDatHDE`, `Daily Check-Ins`, and `Runs`. Hidden tabs are `INITIAL INSTRUCTIONS`, `Setup`, `Dashboard`, `Measurements`, `Weekly Assessment`, `Weekly Check-Ins`, `DshDatHDE`, `Training Plan`, and `Weight Record`.

Formula strings were inspected, not recalculated. Excel formula results, dynamic behavior, and intent of anomalous formulas remain unverified. No external workbook links or defined names were found.

## Product surfaces and input fields

### Setup (`Setup`, hidden)

Input/personalization fields and cell locations:

| Cells | Field |
|---|---|
| `B6` | Weight unit |
| `B7` | Biological gender |
| `B8` | Age |
| `B9` | Starting weight |
| `B10:B11` | Height components; the formula treats them as feet and inches |
| `B12` | Activity-level category |
| `B13` | Lifting sessions per week |
| `B14:B16` | Minimum, target, and dream goal weights |
| `B18` | Goal mode (cutting or bulking) |

`D9`, `D14:D16` mirror the selected unit using `=B$6`. A personal name/personalization field is present on the sheet; its value is intentionally omitted.

### Daily tracking (`Data Input`, visible)

The daily log has a 210-day template in rows `3:212`; row `3` is the starting day. Field headers:

- `A`: week; `B`: day; `C`: date; `D`: daily weight (unit is selected in Setup); `E`: trend-weight display / rate of change.
- `F`: target calories; `G`: daily calories consumed (kcal); `H`: average calories per week (kcal); `I`: estimated maintenance calories.
- `J`: target protein (g); `K`: daily protein consumed (g); `L`: average protein per week (g).
- `M`: target steps; `N`: daily step count; `O`: average step count per week.
- `P`: workout indicator; `Q`: menstruation indicator; `R`: sleep; `T`: fatigue; `V`: stress; `X`: hunger; `Z`: training performance; `AB`: appetite; `AD`: soreness. Alternating columns are used for their weekly averages.

`C3` is a date input; `C4=C3+1` and `C5=C4+1`, continuing through `C212`, so dates advance by one day. Week-summary formulas recur every seven rows at anchors `3, 10, 17, …, 206` (30 anchors); this is a rolling start-date-based week, not evidence of calendar-week alignment. `B3:B212` and week labels are stored text. The first six week-label cells `A3,A10,A17,A24,A31,A38` contain unsupported AI-function formulas; later week labels are static values.

Unit-aware header and examples:

- `D1=CONCATENATE("⚖️ DAILY WEIGHT (",Setup!B6,")")`.
- `E3=CONCATENATE(TEXT(AllDatHDE!K10,"#.00")," ",Setup!B6)`.
- `H3=IFERROR(AVERAGE(G3:G9),"Input Calories First")`; later anchors average their respective seven-row calorie ranges.
- `O3=IFERROR(AVERAGE(N3:N9),"Input Steps First")`.
- Rating averages use the analogous seven-row `AVERAGE` pattern at `S,U,W,Y,AA,AC,AE`. For example, `S3=IFERROR(AVERAGE(R3:R9),"Input Sleep First")` and `AA3=IFERROR(AVERAGE(Z3:Z9),"Input Gym Performance")`.
- `I24=AllDatHDE!M24` and subsequent weekly anchors link to the corresponding smoothed maintenance-calorie value. The sheet notes maintenance computation begins in week 4.

No formulas were found in target columns `F`, `J`, or `M`, or weekly protein-average column `L`; they are not computed by this sheet. Whether they are intended as manual targets or are incomplete template fields needs confirmation.

### Meal/nutrition check-in (`Daily Check-Ins`, visible)

Headers at `A1:F1`: date; proteins; carbs; fats; calories; daily steps. The headers do not specify units for protein/carbs/fats. This tab has no normal calculations or validation rules; `G2` contains an unsupported AI-function formula despite there being no header for column G.

### Runs (`Runs`, visible)

`A1:J1`: week, workout, remarks, date, pace, duration, distance (KM), average HR, max HR, calories. There are no formulas or validation rules. Pace, duration, HR, and calorie units are not specified in the headers. No formula in the workbook connects these rows to the weekly run assessment.

### Other input/template sheets

- `Weekly Assessment` (hidden): 30 weekly rows, with computed trend/rate, gym-performance, and calorie displays plus manual assessment columns `H:K` for weight, gym progression, run, and posing. No validation rules. Its run assessment is not calculated from `Runs`.
- `Weekly Check-Ins` (hidden): wide manually populated week matrix, no formulas or validations. Week headings repeat and skip numbers across its blocks; preserve as separate manual questionnaire/history until block meaning is confirmed.
- `Weight Record` (hidden): `Week`, `Date`, `Weight (Kg)`, `Remarks`; a separate log with a bar chart. It is not referenced by the main calculation engine. The fixed `Kg` label is inconsistent with the Setup unit selector.
- `Training Plan` (hidden): broad, merged, static week-block plan; no formulas. It shows one block labeled weeks 1–13 and another starting again at week 1. Workout details are not reproduced.
- `Measurements` (hidden): helper/series sheet with 53 formulas and no row-1 text headers; examples link weekly points to `AllDatHDE!K10`, `K17`, `K24`, and onward. It appears to be analytics support rather than a standalone entry screen; confirm intended user-facing behavior.

## Calculation and cross-sheet evidence

### Setup-derived targets (`DshDatHDE`, hidden)

Key formulas:

- `B139=IF(Setup!B6="lbs",Setup!B9,Setup!B9*2.204)` converts the selected weight to pounds for downstream calculations.
- `B140=(Setup!B10*12)+Setup!B11` converts the height components to inches.
- `B141` maps activity choice to `1.2`, `1.35`, or `1.45`.
- `B142` maps lifting frequency to `0`, `0.07`, `0.15`, or `0.3`.
- `B143` uses sex-specific BMR equations:
  - male: `66+(6.2*B139)+(12.7*B140)-(6.8*Setup!B8)`
  - female: `655+(4.4*B139)+(4.6*B140)-(4.7*Setup!B8)`
- `B144=IF(Setup!B6="lbs",703*Setup!B9/(B140*B140),703*(Setup!B9*2.204)/(B140*B140))`, the `703 × weight(lb) / height(in)^2` form.
- `B152=B143*(B141+B142)`; this feeds the estimated maintenance/calorie-target calculations.
- `B154=Setup!B9*0.01/4`, `B155=Setup!B9*0.02/4`.
- `B145=IF(Setup!B7="Male",IF(Setup!B6="lbs",CEILING(B152-(Setup!B9*0.0115*500),25),CEILING(B152-(Setup!B9*0.0115*1100),25)),IF(Setup!B6="lbs",CEILING(B152-(Setup!B9*0.01*500),25),CEILING(B152-(Setup!B9*0.01*1100),25)))`.
- `B146=IF(Setup!B7="Male",IF(Setup!B6="lbs",FLOOR(B152-(Setup!B9*0.0075*500),25),FLOOR(B152-(Setup!B9*0.0075*1100),25)),IF(Setup!B6="lbs",FLOOR(B152-(Setup!B9*0.006*500),25),FLOOR(B152-(Setup!B9*0.006*1100),25)))`.
- `B156=IF(Setup!B6="lbs",FLOOR(B152+(B154*500),25),FLOOR(B152+(B154*1100),25))`; `B157` is the same formula with `CEILING` and `B155`.
- `B159=(-44.988+(0.503*Setup!B8)+(10.689*IF(Setup!B7="Male",0,1))+(3.172*B144)-(0.026*(B144*B144))+(0.181*B144*IF(Setup!B7="Male",0,1))-(0.02*B144*Setup!B8)-(0.005*(B144*B144)*IF(Setup!B7="Male",0,1))+(0.00021*(B144*B144)*Setup!B8))*0.01`; `B160=B139-(B139*B159)` derives lean mass.
- `B150=B160*1`; `B151=B160*1.3` define a protein range in grams/day.

`Setup!A21=IF(B18="CUTTING",CONCATENATE("Between ",TEXT(DshDatHDE!B145,"0,0")," and ",TEXT(DshDatHDE!B146,"0,0")," calories per day"),CONCATENATE("Between ",TEXT(DshDatHDE!B156,"0,0")," and ",TEXT(DshDatHDE!B157,"0,0")," calories per day"))`. `Setup!A23=IFERROR(CONCATENATE("Between ",TEXT(DshDatHDE!B150,"0")," and ",TEXT(DshDatHDE!B151,"0")," grams per day"),"Enter Data First")`. These are recommendations; no medical or fitness-safety validation is present.

### Main analytics (`AllDatHDE`, visible)

This sheet has 210 daily calculation rows (`4:213`) mapping to `Data Input` rows `3:212`. Its row-3 fields include date, weigh-ins, calorie entries/display, steps/target, protein/target/hit, trend weight, smoothed TDEE, EMA weekly delta and percentage, total weight lost, sleep/stress/fatigue/hunger, weekly weight SMA and change, calorie SMAs, blank-entry counts/statuses, estimated deficit/surplus, initial estimated TDEE, and overall status. `Y3` and `AB3` are dynamic labels for the selected weight and calorie SMA windows.

Formula coverage by column/range (the repeated daily rows follow the same formulas unless noted):

- `A11:A207`: week index increments at seven-row boundaries; example `A11=A4+1`.
- `B4:B213`: date from Data Input, then previous date + 1; `C4:C213`, `D4:D213`, `F4:F213`, `H4:H213`, and `Q4:T213`: daily input mappings. `E4:E213=D/30`.
- `G4:G207` and `I4:I207`: weekly step/protein targets at 30 weekly anchors. `J4:J213`: protein target status.
- `K4:K213`, `L4:L213`, `M11:M213`: weight EMA, calorie EMA, and smoothed TDEE. `K1:K2`, `L1`, `M1` are parameters; `M2` is a validated selection. `M4:M10` are not formulas.
- `N11:N213`, `O11:O213`, `P5:P213`: weekly change, relative change, and total-weight-lost series.
- `V4:V213`, `W11:W213`, `X11:X213`, `Y4:Y213`: weekly and selected-window weight calculations.
- `AA4:AA213`, `AB4:AB213`: 7-day and selected-window calorie averages.
- `AD4:AG213`: missing-entry counts and weight/calorie status; `AJ4:AJ213`: combined status.
- `AH11:AH213` and `AI11:AI213`: unit-adjusted energy difference and initial estimated TDEE; `AH1` is the unit mirror.

Daily mappings include:

- `B4='Data Input'!C3`, `C4='Data Input'!$D3`, `D4='Data Input'!$G3`, `F4='Data Input'!$N3`, `G4='Data Input'!$M3`, `H4='Data Input'!$K3`, `I4='Data Input'!$J3`.
- `Q4='Data Input'!$R3` (sleep), `R4='Data Input'!$V3` (stress), `S4='Data Input'!$T3` (fatigue), `T4='Data Input'!$X3` (hunger).
- `E4=D4/30` is the calorie-display transform; its intended display scale is not explained.
- `J4=IF(OR(H4="",I$4=""),"Blank",IF(H4<I$4,"No","Yes"))` compares protein entry with target.

Smoothing and trends:

- `K2=IF(Setup!B7="Male","16-Day","20-Day")`; `K2:M2` have dropdown choices `7-Day,10-Day,11-Day,12-Day,13-Day,14-Day,15-Day,16-Day,20-Day`. `K1`, `L1`, and `M1` convert those choices to EMA coefficients: respectively `.25,.1818,.1667,.1538,.1429,.1333,.125,.1176,.0952`. `AH1` mirrors the selected unit.
- The stored coefficient formula in `K1` is `=IF(K2="7-Day",0.25,IF(K2="10-Day",0.1818,IF(K2="11-Day",0.1667,IF(K2="12-Day",0.1538,IF(K2="13-Day",0.1429,IF(K2="14-Day",0.1333,IF(K2="15-Day",0.125,IF(K2="16-Day",0.1176,IF(K2="20-Day",0.0952)))))))))`; `L1` and `M1` use the same mapping with `L2` and `M2`.
- `K4=IF(ISBLANK(C4),Setup!B9,Y4)`. Subsequent trend-weight formulas carry the previous value through missing weigh-ins, otherwise use `alpha*weight+(1-alpha)*previous`; e.g. `K5=IF(ISBLANK(C5),K4,IF(K4="",$C5,K$1*$C5+(1-K$1)*K4))`.
- `L` is a smoothed calorie series based on `AB` (selected-window calorie SMA); e.g. `L5=IF(ISBLANK($D5),L4,IF(L4="",$AB5,L$1*$AB5+(1-L$1)*L4))`.
- `M` is smoothed estimated maintenance/TDEE. It carries the prior value while either status is `Waiting`, initializes from `AI`, then applies `M$1` to `AI`; see `M11=IF(OR(AG11="Waiting",AE11="Waiting"),M10,IF(M10="",AI11,M$1*AI11+(1-M$1)*M10))`.
- Weekly trend change uses the trend weight compared with seven rows earlier, e.g. `N11=IF(ISBLANK($C11),N10,IF(K4="","",K11-K4))`; `O11=IF(N11="","",N11/K4)`. `P` is labeled total weight lost.
- `V/W/X` are a weekly weight SMA, its seven-row change, and percentage change. `AA` is a 7-day calorie SMA; `Y` and `AB` have labels that reference selected weight/calorie windows, but once filled their formulas use fixed 14-row ranges, not the selected periods. For example, `Y17=AVERAGE($C4:$C17)` and `Y18=AVERAGE($C5:$C18)`, with analogous ranges in `AB`. The selected windows do affect EMA coefficients. Other examples: `V11=IF(ISBLANK(C11),V10,AVERAGE($C5:$C11))`; `AB11=IF(ISBLANK($D11),AB10,AVERAGE($D4:$D11))`. Whether to retain fixed averages or honor labels requires a product decision.
- `AH11=IF(N11="","",N11*IF(AH$1="kg",1100,500))` converts weekly weight change to an estimated daily calorie difference; `AI11=IF(OR(N11="",L11=""),"",L11-AH11)`.
- `AD/AF` count blank weigh-in/calorie rows over a rolling window (10 entries once enough history exists). `AE/AG` label each series `Waiting` or `Updating` against row-1 thresholds `AE1=5` and `AG1=3`. `AJ=IF(AND(AE4="Updating",AG4="Updating"),"Updating","Holding")`.

### Daily Check-Ins and formula-based import

`Data Input` formula ranges are `C4:C212` (daily date increments), six AI-stub week-label cells in `A3:A38`, 30 weekly-anchor formulas each in `E,H,O,S,U,W,Y,AA,AC,AE`, 27 maintenance-calorie links in `I24:I206`, and linked input columns `G,K,N` in rows `91:212` (with the anomalies noted below).

For `Data Input` rows `91:212`, columns `G/K/N` link by row position to `Daily Check-Ins` columns `E/B/F`. Examples: `G91='Daily Check-Ins'!E140`, `K91='Daily Check-Ins'!B140`, `N91='Daily Check-Ins'!F140`; the final row links to source row 261. Earlier rows in those columns are stored directly. These are row-position links, not date-keyed lookups; the workbook provides no date reconciliation or import-service evidence.

`Weekly Assessment` uses the daily summary at weekly anchors. Examples: `B3=AllDatHDE!O17`, `C3=B3*100`, `D2='Data Input'!AA3`, `E2=IF(ISTEXT(D2),0,D2)`, `F2='Data Input'!H3`, and `G2=IF(ISTEXT(F2),0,F2)/1000`. Subsequent rows step through the 7-day anchors. Gym and calorie values are transformed for display; columns `H:K` remain manual.

## Date logic, dashboard, charts, and targets

- `DshDatHDE!L4=TODAY()` supplies the helper/dashboard date. Date rows are generated around that anchor; lookup formulas such as `DshDatHDE!B2=IFNA(VLOOKUP(A2,AllDatHDE!B4:U103,2),"")` query only `AllDatHDE!B4:U103` (100 daily rows), not the full 210-day calculation range.
- Hidden `Dashboard` has two KPIs: `B4=CONCATENATE(TODAY()-AllDatHDE!B46," DAYS")`; `B10=CONCATENATE(ROUND(AllDatHDE!K213-AllDatHDE!K46,2)," KG")`.
- `Weight Record` contains two interleaved weekly date sequences: `B9=B7+7`, `B10=B8+7`, `B11=B9+7`, and `B12=B10+7`. The reason for the two sequences and their import semantics remain unverified.
- Dashboard chart 1 is a bar chart with series `AllDatHDE!$N$4:$N$1000`, dates `AllDatHDE!$B$4:$B$1000`, series label from `AllDatHDE!$N$3`.
- Dashboard chart 2 is a line chart with series `AllDatHDE!$C$47:$C$1000`, dates `AllDatHDE!$B$47:$B$1000`, series label from `AllDatHDE!$C$46`.
- `Weight Record` has a bar chart using `B1:B955` as categories and `C1:C955` as values.

The dashboard KPI references are fixed row numbers, and `B10` hard-codes `KG` even though Setup offers pounds. The chart ranges extend to row 1000, beyond the populated calculation series. These may be deliberate template choices but should be confirmed for an app.

## Validation and missing input behavior

- `Setup`: dropdowns at `B7` (`Male,Female`), `B6` (`kg,lbs`), `B13` (four lifting-frequency choices), `B12` (three activity levels), and `B18` (`CUTTING,BULKING`). No validation was found for age, height, starting weight, or goal weights.
- `Data Input`: ratings `T,V,X,Z,AB,AD` allow `1.0–5.0`; sleep `R` allows `5.0,4.0,3.0,2.0,1.0`. No input-level validation was found for dates, calorie/protein/step amounts, workout, or menstruation.
- `AllDatHDE`: dropdowns at `K2:M2` for smoothing windows and `AH1` for `kg,lbs`.
- `DshDatHDE!L4`: custom date validation.
- `Runs`, `Daily Check-Ins`, `Weekly Check-Ins`, `Weekly Assessment`, `Training Plan`, and `Weight Record` have no data validation rules.
- Rating meanings/labels (what each score means) are not specified. Boolean/choice semantics for workout and menstruation are not enforced. The template's weekly-average fallback messages are inconsistent: `AC3` says “Input Stress First” for appetite; `AE3` says “Input Hunger First” for soreness; `U3` contains the “Fatgue” spelling.
- No formula computes the labeled weekly protein average (`Data Input!L`), and the workbook does not explain how to handle skipped days, duplicate dates, late entries, or unit changes after logging.

## Formula faults and implementation risks

The following are exact stored-formula anomalies, not recalculated outcomes:

1. **Explicit broken references:** `Data Input!K188=#REF!` and `AllDatHDE!Q61=#REF!`.
2. **Discontinuous positional links:** `Data Input!G162='Daily Check-Ins'!G158` breaks the surrounding `G`-to-`E` source mapping (the neighboring formulas map to `Daily Check-Ins!E`). The `K` source has `K188=#REF!`, `K189='Daily Check-Ins'!B237`, and `K190='Daily Check-Ins'!B239`, skipping a source row relative to adjacent mappings. In `AllDatHDE`, `Q61=#REF!`; `Q62='Data Input'!$R60` and `Q63='Data Input'!$R62` skip an input row relative to the surrounding sequence. Intended corrections need confirmation.
3. **References to absent worksheets:** `DshDatHDE!B27` and `A28` reference `'W2'!C6`; `DshDatHDE!B28` references `'W1'!C6`. Neither `W1` nor `W2` exists among the 13 tabs. These formulas select/label goal direction and cannot be ported reliably without recovering the missing choice/state semantics.
4. **Protein target comparison freezes:** `AllDatHDE!J` uses weekly target cells through `I$95`, but formulas from `J102` through `J213` refer to `I$102`. For example, `J213=IF(OR(H213="",I$102=""),"Blank",IF(H213<I$102,"No","Yes"))`. Confirm whether the target should advance by week.
5. **Total-weight-lost baseline drifts:** `AllDatHDE!P` initially uses `K$4` and then `Setup!B9`; from `P105` it begins changing the Setup reference (`P105` uses `Setup!B10`) and ends at `P213` using `Setup!B118`. Setup only has 23 rows. This strongly suggests a relative-reference/copy error; later values may be based on unrelated or blank Setup cells instead of starting weight. Confirm intended baseline, likely `Setup!B9`, before implementation.
6. **Unsupported AI formulas:** `Data Input!A3,A10,A17,A24,A31,A38` and `Daily Check-Ins!G2` contain `__xludf.DUMMYFUNCTION("AI(...)")` wrappers with an `=AI(...)` fallback string. Their outputs are not portable formula behavior and must not be treated as reliable week labels or app-generated data.
7. **Goal/weight units and chart output:** `Dashboard!B10` hard-codes “KG”; `Weight Record!C1` hard-codes “Weight (Kg)”. Both conflict with the selectable `Setup!B6` unit.
8. **Lookup horizon:** the dashboard helper's `VLOOKUP` range ends at `AllDatHDE!U103`; it may omit later dates in the 210-day source.

The file contains no HealthKit/Apple Health connector, external API, or workbook link. The only observed integrations are internal cross-sheet formulas. Any native app sync/import behavior, week-label generation, run-to-assessment logic, rating semantics, and handling of missing/duplicate dates require product decisions or source-owner confirmation.
