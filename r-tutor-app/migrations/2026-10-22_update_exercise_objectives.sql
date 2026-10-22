-- Brings exercises.title / exercises.learning_objective in line with the
-- 2026-10-22 course-wide rework (harder, read/predict/debug-oriented
-- exercises). The tutor chat is given learning_objective as context, so it
-- should describe the skill being practiced -- never the answer itself.
-- Updates only; exercise_key values (and so all logged attempts/chats) are
-- unchanged. Paste into the Supabase SQL Editor and run.

update exercises set
  title = 'Switch off a leftover line',
  learning_objective = 'Use # to comment out (not delete) one line in a short script so that it no longer runs, after working out which line is changing the data and making the final result wrong.'
where exercise_key = 'module2_comment_out';

update exercises set
  title = 'Fix the errors',
  learning_objective = 'Read R error messages one at a time and fix each problem they point to -- a misspelled function name, and a word used without quotation marks that R treats as an object name -- until the code runs and prints the intended text.'
where exercise_key = 'module2_fix_error';

update exercises set
  title = 'Update the total',
  learning_objective = 'Understand that assignment stores a value, not a formula: when an input variable changes, anything calculated from it earlier keeps its old value until it is recalculated. Fix the code so the final result reflects the new input, computed from the variables rather than typed in.'
where exercise_key = 'module3_assignment';

update exercises set
  title = 'Pull out two elements',
  learning_objective = 'Use square-bracket indexing with a vector of positions to retrieve several specific elements of a vector at once, rather than typing the values in by hand.'
where exercise_key = 'module3_vectors';

update exercises set
  title = 'Count the hot days',
  learning_objective = 'Recognize that a single = assigns rather than compares, so code that was meant to compare can silently overwrite a variable and still run; fix it with a real comparison, and use sum() on a TRUE/FALSE vector to count how many values meet a condition.'
where exercise_key = 'module3_fix_comparison';

update exercises set
  title = 'Check the AI''s conversion',
  learning_objective = 'Verify code that translates a math formula (Fahrenheit to Celsius, using the provided vector temps_f) by testing it against values whose answer is already known, then correct how the expression is written so R computes the formula as intended -- understanding the order in which R applies arithmetic operators.'
where exercise_key = 'module3_formula_to_code';

update exercises set
  title = 'Fix the receipt',
  learning_objective = 'Debug a short calculation script with several problems at once -- some that stop it from running and one that lets it run but produce a wrong (yet plausible-looking) number -- by reading each error message and sanity-checking the final result against a rough expected value.'
where exercise_key = 'module3_cumulative';

update exercises set
  title = 'Heaviest fish per species',
  learning_objective = 'Group a data frame with group_by() and compute more than one summary per group with summarize(), including a count of rows per group, while noticing and correctly handling missing values that would otherwise turn a summary into NA.'
where exercise_key = 'module4_group_summarize';

update exercises set
  title = 'Color by species',
  learning_objective = 'Modify an existing ggplot2 scatter plot so a visual property (point color) is mapped to a data column -- understanding the difference between mapping a column inside aes() and setting a fixed value outside it.'
where exercise_key = 'module5_scatter';

update exercises set
  title = 'Fix the bar chart',
  learning_objective = 'Fix a bar chart built from summarized data that runs but shows the wrong thing, by understanding the difference between a geom that counts rows itself and one that draws bars at heights already present in the data.'
where exercise_key = 'module5_bar';

update exercises set
  title = 'Debug the plot',
  learning_objective = 'Debug a filter-then-plot pipeline with two problems -- one that stops it from running (how ggplot2 layers are joined) and one that lets it run but silently plots the wrong data (how filter() matches text values) -- by reading the error and checking whether the plot actually shows what was intended.'
where exercise_key = 'module5_cumulative';

update exercises set
  title = 'Fix the model',
  learning_objective = 'Read an lm() formula (outcome ~ predictor) and fix a model whose outcome and predictor are reversed, then extract the slope for the intended predictor with coef() -- understanding why the wrong direction produces NA for that coefficient.'
where exercise_key = 'module6_linear_regression';

update exercises set
  title = 'Check the AI''s RMSE',
  learning_objective = 'Recognize an implausible result (an RMSE of 0, implying perfect predictions) from code that runs without error, and fix how the root mean squared error is computed from actual_weights and predicted_weights so that each difference is handled before averaging.'
where exercise_key = 'module6_rmse';
