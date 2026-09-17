# Checkpoints & Feedback

Do each checkpoint **in real RStudio on your own computer**, at the point in the course listed below -- not inside the course website itself. Fill in your notes right after each one, while it's fresh, instead of waiting until the end.

If you get completely stuck on a checkpoint, that's useful information too -- write down where you got stuck and move on, don't spend more than ~15 minutes stuck on any one step.

---

## Checkpoint 1 -- after finishing Module 3 ("Data"), before starting Module 4

**File you need:** `checkpoint1_seedling_heights.csv`

1. Save that file somewhere on your computer you can find again (e.g. Desktop, or a new folder called `r_practice`).
2. Open RStudio and make sure your working directory is that same folder (File > Session > Set Working Directory > Choose Directory, or open an RStudio Project there).
3. Read the file into R and take a look at it (you learned how to do both of these in Module 3).
4. Answer, in a sentence each:
   - How many rows and columns does the data have?
   - What R data type is the `height_cm` column?
   - What are the two values in the `treatment` column?

**Notes (what happened, what was confusing, where you got stuck):**




---

## Checkpoint 2 -- after finishing Module 4 ("Clean Up"), before starting Module 5

**File you need:** `checkpoint2_bird_counts_messy.csv`

This one is intentionally messier -- real data usually looks like this, not like the tidy example in the course.

1. Read the file into R.
2. Using what you learned in Module 4, produce a cleaned-up table that shows: the average bird `Count` at each site, **ignoring the missing (NA) count values** rather than treating them as zero, sorted from highest average to lowest.
3. Along the way you'll need to deal with the column names (`Site.Name`, `Bird.Species`, etc.) -- clean those up too, however makes sense to you.
4. Write down the R code you ended up using.

**Notes (what happened, what was confusing, where you got stuck, your final code):**




---

## Checkpoint 3 -- after finishing Module 5, course complete

This is the "does this actually transfer" test -- no file from me this time.

1. Find a real spreadsheet or CSV file of your own (something on your computer already, or something you download -- doesn't matter what it's about).
2. Import it into R.
3. Look at it (how many rows/columns, what types are the columns).
4. Make at least one plot from it, of anything you want.
5. If anything about it doesn't fit what the course taught you (a totally different structure, a plot type you weren't shown, etc.), note that too -- that's useful.

**Notes (what data you used, what happened, where you got stuck):**




---

## Checkpoint 4 -- Capstone preview, after finishing Module 6

**Files you need (same folder together):** `capstone_model_comparison.R` and `capstone_fish_survey.csv`

This previews where the course is ultimately headed: being handed a script that fits real models, and being able to make sense of -- and dig a little into -- what it's telling you. Most of this script is given to you and just needs to be run, but Step 9 near the bottom asks you to write a few lines yourself, reusing the `filter()` skill from Module 4 and the RMSE skill from Module 6.

1. Open `capstone_model_comparison.R` in RStudio.
2. Run Steps 1-8 top to bottom (it may install one extra package the first time -- that's expected).
3. At Step 9, fill in the three `FIXME`s yourself (see the comment right above it for what goes there), then run that part too.
4. Answer the five questions at the bottom of the script, in your own words.
5. Note anything that errored, looked broken, or you didn't understand -- including if a plain-language explanation of any term used (RMSE, "training"/"test" data, etc.) would have helped, and including whether Step 9 felt like a reasonable amount of your own code to write at this point, or too much/too little.

**Your answers to Q1-Q5, and any notes:**




---

## Bugs

List anything that didn't work as expected, anywhere in the course (not just the checkpoints). One row per bug is fine.

| Where (module/topic) | What happened | Screenshot? |
|---|---|---|
|   |   |   |
|   |   |   |

---

## The AI tutor chat

Answer these for your overall impression across however many times you used it:

- Did it ever feel robotic or generic, rather than like it was actually responding to your specific attempt? __
- Did it ever just give you the answer outright, instead of helping you get there yourself? __
- Did it ever say something that was flatly wrong? __
- Did response time feel reasonable, or did you find yourself waiting? __
- Anything it did that was genuinely helpful and worth keeping exactly as-is? __

---

## Getting help outside the course

- At any point, did you look anything up outside the course -- Google, ChatGPT or another AI tool, Stack Overflow, a friend, anything at all? __
- If yes: where in the course were you (which module or checkpoint), what were you trying to figure out, and did the course's own tutor chat not come to mind, or did you try it first and still feel like you needed more? __

---

## Visuals -- screenshots, clips, diagrams, anything visual

The whole course right now is text (plus code output and plots you generate). We're deciding whether adding real screenshots, short screen-recording clips, or diagrams anywhere would help -- not just in the install section, anywhere at all.

- At any point in the course, would seeing an actual screenshot or a short clip (rather than just reading text) have made something easier to follow? Where, specifically? __
- Anything else visual -- a diagram, an example of what correct output should look like, a different format entirely -- that would have helped anywhere? __

---

## Anything else

Open space for anything that doesn't fit above -- pacing, wording, things you'd change, things that worked better than expected.



