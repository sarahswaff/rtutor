# R Tutor — Technical Assessment (20 questions)

Multiple choice, one correct answer each. Ordered by module; difficulty marked
**[E]** easy, **[M]** medium, **[H]** hard. Questions that reference `fish_clean`
use the same data set taught in Modules 4–6:

| fish_id | species         | length_mm | weight_g | lake_site  |
|--------:|-----------------|----------:|---------:|------------|
| 1       | Bluegill        | 152       | 45       | North Lake |
| 2       | Bluegill        | 148       | 42       | North Lake |
| 3       | Largemouth Bass | 310       | NA       | South Lake |
| 4       | Largemouth Bass | NA        | 610      | South Lake |
| 5       | Yellow Perch    | 205       | 98       | North Lake |
| 6       | Yellow Perch    | 198       | 95       | South Lake |
| 7       | Bluegill        | 160       | 50       | North Lake |
| 8       | Largemouth Bass | 295       | 580      | South Lake |
| 9       | Yellow Perch    | 210       | NA       | North Lake |
| 10      | Bluegill        | 145       | 40       | South Lake |

(If students take this without the table, give it to them — the questions test
reasoning about the data, not memory of it.)

---

## Questions

**1. [E] (Module 1)** You just ran `x <- 42`. Which RStudio pane will now list `x`?

- A. Console
- B. Environment
- C. Files
- D. Viewer

**2. [M] (Module 1)** You run `read.csv("bird_counts.csv")` and get
`cannot open file 'bird_counts.csv': No such file or directory`. The file
definitely exists on your computer. What is the most likely cause?

- A. The file is too large for R to open
- B. `read.csv()` requires the `readr` package to be loaded first
- C. R's working directory is not the folder that contains the file
- D. CSV files must be converted to Excel before R can read them

**3. [E] (Module 2)** What happens when you run this line?

```r
# mean(c(1, 2, 3))
```

- A. It prints `2`
- B. It returns an error because `#` is not valid R
- C. It prints the text `mean(c(1, 2, 3))`
- D. Nothing — R treats the whole line as a comment

**4. [M] (Module 2)** Yesterday you ran `install.packages("dplyr")`. Today you open a
new RStudio session and `filter()` gives `could not find function "filter"`. What
should you run?

- A. `install.packages("dplyr")` again
- B. `help(filter)`
- C. `update.packages()`
- D. `library(dplyr)`

**5. [M] (Module 2)** Which error message most directly tells you that you made a
typo in an object's name?

- A. `Error: object 'fish_cleen' not found`
- B. `Error: unexpected ')' in "mean(x))"`
- C. `Error in library(ggplot3): there is no package called 'ggplot3'`
- D. `Warning: Removed 3 rows containing missing values`

**6. [E] (Module 3)** What does this return?

```r
x <- c(4, 8, 15, 16)
x[2]
```

- A. `4`
- B. `8 15 16`
- C. `4 8`
- D. `8`

**7. [M] (Module 3)** What does `class(c(1, "2", 3))` return?

- A. `"numeric"`
- B. `"list"`
- C. `"character"`
- D. An error, because a vector can't mix types

**8. [M] (Module 3)** The Pythagorean theorem is c = √(a² + b²). With `a <- 3` and
`b <- 4`, which line correctly computes `c` as `5`?

- A. `sqrt(a^2) + b^2`
- B. `sqrt(a^2 + b^2)`
- C. `sqrt(a + b)^2`
- D. `(a^2 + b^2)^2`

**9. [H] (Module 3)** What does this print?

```r
x <- c(5, NA, 3)
x > 4
```

- A. `TRUE FALSE FALSE`
- B. `TRUE NA FALSE`
- C. `TRUE FALSE`
- D. `NA`

**10. [E] (Module 4)** How many rows does this return?

```r
fish_clean |> filter(species == "Bluegill") |> nrow()
```

- A. 2
- B. 3
- C. 4
- D. 10

**11. [M] (Module 4)** Which line causes an error?

- A. `fish_clean |> filter(lake_site = "North Lake")`
- B. `fish_clean |> filter(lake_site == "North Lake")`
- C. `fish_clean |> filter(length_mm > 200)`
- D. `fish_clean |> select(species, weight_g)`

**12. [M] (Module 4)** What does `mean(fish_clean$length_mm)` return?

- A. `202.56`
- B. `182.3`
- C. An error
- D. `NA`

**13. [H] (Module 4)** What does this return?

```r
sum(fish_clean$weight_g > 50, na.rm = TRUE)
```

- A. `4`
- B. `1383`
- C. `5`
- D. `NA`

**14. [H] (Module 4)** A student wants to keep only fish that have a recorded weight.
They write `fish_clean |> filter(weight_g != NA)`. What actually happens?

- A. It correctly returns the 8 fish with a weight
- B. It returns all 10 rows unchanged
- C. It returns 0 rows, because any comparison with `NA` is `NA`; they should use `filter(!is.na(weight_g))`
- D. It errors, because `!=` can't be used inside `filter()`

**15. [H] (Module 4)** What is `avg` in the result?

```r
fish_clean |>
  filter(lake_site == "North Lake") |>
  summarise(avg = mean(weight_g))
```

- A. `58.75`
- B. `NA`
- C. `55.0`
- D. An error, because `summarise()` needs `group_by()` first

**16. [H] (Module 4)** What is the value in the **first row** of `mean_len`?

```r
fish_clean |>
  filter(!is.na(length_mm)) |>
  group_by(species) |>
  summarise(mean_len = mean(length_mm)) |>
  arrange(desc(mean_len))
```

- A. `302.5` (Largemouth Bass)
- B. `204.3` (Yellow Perch)
- C. `151.25` (Bluegill)
- D. `NA` (Largemouth Bass)

**17. [M] (Module 5)** You've already computed `mean_weight` for each species with
`summarise()` and want a bar for each species whose height is that mean. Which geom?

- A. `geom_bar()`
- B. `geom_histogram()`
- C. `geom_col()`
- D. `geom_point()`

**18. [H] (Module 5)** This plot runs, but with a warning:

```r
ggplot(fish_clean, aes(x = length_mm, y = weight_g)) + geom_point()
```

How many points actually appear on the plot?

- A. 10
- B. 8
- C. 7
- D. 0 — ggplot won't draw anything when there are NAs

**19. [M] (Module 6)** A model predicting `weight_g` from `length_mm` has an RMSE of
`38`. What does that mean?

- A. Predictions are typically off by about 38 grams
- B. The model explains 38% of the variation in weight
- C. Predictions are typically off by about 38 millimeters
- D. 38 of the fish were predicted incorrectly

**20. [H] (Module 6)** `model <- lm(weight_g ~ length_mm, data = fish_clean)`. You
get `coef(model)["length_mm"]` = `3.2` and an R² of `0.85`. Which statement is correct?

- A. Every fish weighs 3.2 times its length, and the model is right 85% of the time
- B. The model's predictions are off by 3.2 g on average, and 0.85 is the p-value
- C. Each extra gram of weight predicts about 3.2 mm more length, and 85% of fish fall on the line
- D. Each extra millimeter of length predicts about 3.2 g more weight, and length explains about 85% of the variation in weight

---

## Answer key

| #  | Ans | Why |
|---:|:---:|-----|
| 1  | B | Environment lists objects in the current session. |
| 2  | C | Relative paths resolve against the working directory (`getwd()`). |
| 3  | D | Everything after `#` is a comment. |
| 4  | D | Install once per computer; `library()` once per session. |
| 5  | A | "object ... not found" = R doesn't know that name — usually a typo or not-yet-run line. |
| 6  | D | R indexes from 1. |
| 7  | C | A vector holds one type; mixing forces everything to character. |
| 8  | B | A = 19, C = 49, D = 625. Parentheses control what goes under the root. |
| 9  | B | Comparisons with `NA` give `NA`, element by element. |
| 10 | C | Rows 1, 2, 7, 10. |
| 11 | A | `=` assigns/names arguments; `==` tests equality. |
| 12 | D | Row 4 is `NA`; `mean()` returns `NA` without `na.rm = TRUE`. |
| 13 | A | TRUEs are 98, 95, 610, 580 → 4. 50 is not > 50 (C is the `>=` trap); B sums the weights instead of counting. |
| 14 | C | `x != NA` is always `NA`, and `filter()` drops `NA` rows. Verified: returns 0 rows. |
| 15 | B | Fish 9 (North Lake) has `NA` weight and there's no `na.rm = TRUE`. A = the answer if they'd added it. |
| 16 | A | Bass: (310 + 295) / 2 = 302.5 once the NA row is filtered out. D is the trap if the filter weren't there. |
| 17 | C | `geom_col()` uses the y value as-is; `geom_bar()` counts rows. |
| 18 | C | Fish 3, 4, 9 each have an NA in x or y → 3 removed. |
| 19 | A | RMSE is in the units of what's being predicted (grams). |
| 20 | D | Slope = change in y per 1-unit change in x; R² = share of variation explained. |

**Difficulty mix:** 4 easy (1, 3, 6, 10) · 9 medium (2, 4, 5, 7, 8, 11, 12, 17, 19) · 7 hard (9, 13, 14, 15, 16, 18, 20).

**Answer distribution:** A ×5, B ×4, C ×6, D ×5.

Answers to 7, 9, 10, 12, 13, 14, 15, 16, 18 and the arithmetic in 8 were checked by
running the code in R against `fish_clean`.
