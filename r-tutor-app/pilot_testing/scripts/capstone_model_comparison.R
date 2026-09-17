# ===========================================================================
# Capstone preview: comparing two models on the fish survey data
#
# You don't need to write any of this -- it's given to you, just like a real
# script from an instructor or teammate would be. Your job is to RUN it and
# then answer the questions at the bottom of this file, in plain language.
#
# Before running: put "capstone_fish_survey.csv" in the same folder as this
# script, then set your working directory to that folder (Session > Set
# Working Directory > To Source File Location in RStudio), or open this
# script from an RStudio Project rooted in that folder.
# ===========================================================================

# ---- 1. Load the data -----------------------------------------------------
fish <- read.csv("capstone_fish_survey.csv")
str(fish)
head(fish)

# ---- 2. Look at the raw relationship --------------------------------------
# Does the relationship between length and weight look like a straight line,
# or a curve? Look at the plot that pops up.
plot(fish$length_mm, fish$weight_g,
     main = "Fish weight vs. length",
     xlab = "Length (mm)", ylab = "Weight (g)",
     pch = 19, col = "steelblue")

# ---- 3. Split the data into a training set and a test set -----------------
# We fit ("train") each model on 80% of the fish, then check how well it
# predicts the weight of the other 20% -- fish the model never saw. This is
# the standard way to check whether a model actually generalizes, rather
# than just memorizing the data it was given.
set.seed(1)
n <- nrow(fish)
train_rows <- sample(seq_len(n), size = round(0.8 * n))
train <- fish[train_rows, ]
test  <- fish[-train_rows, ]

# ---- 4. Model 1: a straight-line (linear) model ----------------------------
model_linear <- lm(weight_g ~ length_mm, data = train)
summary(model_linear)

# ---- 5. Model 2: a machine learning model (random forest) -----------------
# This one can bend and curve to fit the data, instead of being forced into
# a straight line. It needs one extra package -- if you don't have it yet,
# this line installs it automatically.
if (!requireNamespace("randomForest", quietly = TRUE)) {
  install.packages("randomForest")
}
library(randomForest)

set.seed(1)
model_forest <- randomForest(weight_g ~ length_mm, data = train)

# ---- 6. Have both models predict the test fish -----------------------------
pred_linear <- predict(model_linear, newdata = test)
pred_forest <- predict(model_forest, newdata = test)

# Bundle the test fish together with both models' predictions into one
# table -- you'll use this again in Step 9 below.
results <- data.frame(
  species     = test$species,
  length_mm   = test$length_mm,
  actual      = test$weight_g,
  pred_linear = pred_linear,
  pred_forest = pred_forest
)

# ---- 7. Score each model: how far off were its guesses, on average? --------
# RMSE = "root mean squared error" -- roughly, the typical number of grams
# each model's prediction was off by. Lower RMSE = better predictions. (This
# is the exact same formula you used by hand in Module 6.)
rmse <- function(actual, predicted) sqrt(mean((actual - predicted)^2))

rmse_linear <- rmse(results$actual, results$pred_linear)
rmse_forest <- rmse(results$actual, results$pred_forest)

cat("Straight-line model RMSE:", round(rmse_linear, 1), "grams\n")
cat("Random forest model RMSE:", round(rmse_forest, 1), "grams\n")

# ---- 8. Visualize both models' fit against the actual data -----------------
plot(fish$length_mm, fish$weight_g,
     main = "Actual weight vs. both models' predictions",
     xlab = "Length (mm)", ylab = "Weight (g)",
     pch = 19, col = "gray50")
new_lengths <- data.frame(length_mm = seq(min(fish$length_mm), max(fish$length_mm), length.out = 200))
lines(new_lengths$length_mm, predict(model_linear, newdata = new_lengths),
      col = "firebrick", lwd = 2)
lines(new_lengths$length_mm, predict(model_forest, newdata = new_lengths),
      col = "forestgreen", lwd = 2)
legend("topleft", legend = c("Straight-line model", "Random forest model"),
       col = c("firebrick", "forestgreen"), lwd = 2, bty = "n")

# ===========================================================================
# ---- 9. YOUR CODE: does this hold up for every species? -------------------
# Steps 1-8 lumped all three species together. That can hide a lot -- a
# model can look great overall while actually doing much better on one
# group than another. Now that you have `results` (from Step 6) and the
# `filter()` skill from Module 4, check each species on its own.
#
# Below, filter `results` down to just one species at a time, then this
# reuses the same `rmse()` function from Step 7 on each subset. Replace
# each FIXME with a species name in quotes -- "Bluegill", "Largemouth Bass",
# or "Yellow Perch".
library(dplyr)

bluegill <- results |> filter(species == FIXME)
bass     <- results |> filter(species == FIXME)
perch    <- results |> filter(species == FIXME)

cat("Bluegill      -- linear:", round(rmse(bluegill$actual, bluegill$pred_linear), 1),
    " | forest:", round(rmse(bluegill$actual, bluegill$pred_forest), 1), "\n")
cat("Largemouth Bass -- linear:", round(rmse(bass$actual, bass$pred_linear), 1),
    " | forest:", round(rmse(bass$actual, bass$pred_forest), 1), "\n")
cat("Yellow Perch  -- linear:", round(rmse(perch$actual, perch$pred_linear), 1),
    " | forest:", round(rmse(perch$actual, perch$pred_forest), 1), "\n")
# ===========================================================================

# ===========================================================================
# YOUR TURN -- answer these in your own words (a sentence or two each is
# plenty). Put your answers in a comment right here in the script, or in
# your reply to the pilot-test message -- whichever is easier for you.
#
# Q1. Look at the plot from Step 2 (before either model was fit). Does the
#     relationship between length and weight look like a straight line, or
#     does it curve? What made you say that?
#
# Q2. Look at the plot from Step 8. Which line -- red (straight-line model)
#     or green (random forest) -- looks like it follows the actual dots
#     more closely?
#
# Q3. Which model had the lower overall RMSE (Step 7)? Does that match what
#     you saw in the plot in Q2?
#
# Q4. Look at your per-species output from Step 9. Does the random forest
#     beat the straight-line model for ALL three species, or is its
#     advantage bigger for some species than others? Any guess as to why?
#
# Q5. In plain language, what would you tell someone about which model to
#     trust more for predicting a new fish's weight from its length -- and
#     why?
# ===========================================================================
