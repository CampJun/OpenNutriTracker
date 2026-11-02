# Energy Expenditure

How the app estimates how much energy a user burns per day, which anchors their daily calorie goal.

## Language

**TDEE** (Total Daily Energy Expenditure):
The estimated kcal a user burns in a day of sedentary living, excluding exercise and before any weight-goal adjustment. Always BMR × 1.2; exercise reaches the calorie goal only through Logged Activities.
_Avoid_: maintenance calories, TEE

**Logged Activity**:
A workout or other exercise the user records (manually or imported from a health store), whose kcal above resting burn are added to that day's calorie goal on top of TDEE.
_Avoid_: exercise, workout (as the domain term)

**Daily Steps**:
The user's step count for a day, entered from their step tracker, converted to net walking kcal from total body weight and height and added to that day's calorie goal. A day has at most one value; entering a new one replaces it. Walking or running is credited through Daily Steps, not also as a Logged Activity.
_Avoid_: step activity, step log

**BMR** (Basal Metabolic Rate):
The estimated kcal a user burns at complete rest, computed with Katch-McArdle.
_Avoid_: RMR, REE, resting calories

**Katch-McArdle**:
The equation the app uses for BMR, based solely on Lean Body Mass. It is the only energy equation in this fork.
_Avoid_: calculator, formula (as a name for it)

**Lean Body Mass**:
Body weight minus fat mass, taken from the current Body Fat Reading. It does not change when the user logs a new weight; only a new Body Fat Reading changes it.
_Avoid_: LBM (in user-facing text), fat-free mass, muscle mass

**Body Fat Percentage**:
The share of body weight that is fat, from 0 to 100.
_Avoid_: body fat, BF

**Body Fat Reading**:
A Body Fat Percentage together with the body weight at the moment it was measured. The user has at most one current reading; entering a new one replaces it.
_Avoid_: body fat measurement, body composition
