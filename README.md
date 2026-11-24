# Australian Wine Sales Forecasting

In every year from 1980 through 1994, Australian Sparkling wine sales peaked in December. The timing was predictable. The harder question was **how much wine would sell at the peak**. This project uses 15 years of monthly sales to compare forecasting methods for Sparkling and five other wine varieties. An interactive R Shiny app lets readers change the training period, inspect the fitted models, and compare predictions against sales that were held back for testing.

[Explore the live forecasting app](https://01a20bef-54c0-c0e4-a19a-66c1ab32bd3d.share.connect.posit.cloud/) · [View the source on GitHub](https://github.com/YubiQuinzon/australian-wine-forecasting)

**Main finding.** Among the three models in the app, exponential smoothing (ETS) earned the lowest 1994 forecast error for Fortified, Sparkling, and Rosé. ARIMA led for Red, Dry white, and Sweet white. I also checked what would happen if someone simply used last year's sales for each month. That simple rule beat all three fitted models for Fortified and Rosé. The model choice depends on the variety and on which alternatives enter the comparison.

[Findings](#findings) · [Data](#data) · [Forecasting methods](#forecasting-methods) · [Using the app](#using-the-app) · [Running locally](#running-locally) · [Repository guide](#repository-guide) · [Limitations](#limitations)

## Findings

### How accurately could each model forecast 1994?

Each model received the same 168 months of training data, January 1980 through December 1993. From that December cutoff it forecast the next 12 months in one pass. January was a one-month-ahead forecast and December was a twelve-month-ahead forecast. The table pools errors over the observed months of 1994.

Values are **root mean squared error (RMSE) in thousand litres**. Lower is better. Bold identifies the best of the three interactive models in each row. The last column is a separately calculated seasonal naïve benchmark. Its calculation is included [below](#reproduce-the-seasonal-naive-benchmark).

| Wine variety | Months scored | Seasonal regression | ETS | ARIMA | Same month last year |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fortified | 12 | 426.53 | **318.90** | 328.50 | 273.09 |
| Sparkling | 12 | 459.05 | **444.48** | 461.46 | 583.92 |
| Red | 12 | 319.28 | 297.16 | **257.86** | 402.87 |
| Dry white | 12 | 556.28 | 562.69 | **484.39** | 631.66 |
| Sweet white | 12 | 112.76 | 61.11 | **51.27** | 53.68 |
| Rosé | 10 | 9.80 | **9.17** | 9.36 | 6.66 |

**Sparkling had a consistent peak and an uncertain peak size.** Recorded sales rose from 1.197 million litres in January 1994 to 5.999 million in December. ETS reduced full-year RMSE by about 24% compared with repeating 1993. Its advantage over seasonal regression was only about 3%. The seasonal pattern was strong enough for a simple regression to capture much of it.

**Red showed a clearer payoff from model selection.** ARIMA reduced RMSE from 402.87 to 257.86 thousand litres relative to the prior-year benchmark, a 36% reduction. It also beat ETS, the next-best fitted model, by about 13%. For Sweet white, ARIMA led as well, but its reduction against the prior-year benchmark was only about 4.5%. A first-place ranking alone hides that difference.

**Low absolute error can still mean appreciable percentage error.** For Fortified, ETS missed by an average of 242.65 thousand litres in absolute terms, or 10.24% when averaged as monthly percentage errors. For Rosé, those figures were 7.20 thousand litres and 13.01%. Compare absolute errors within a variety when choosing its model. Use the sales scale and the number of observed months to put cross-variety comparisons in context.

### What did the next December forecast look like?

After model comparison, the app can refit each model through December 1994. For Sparkling, the three point forecasts for December 1995 were approximately **5.94 million litres from ETS, 6.01 million from seasonal regression, and 6.16 million from ARIMA**. Their central estimates were close, but the ETS 80% prediction interval ran from **4.17 to 7.70 million litres**. Agreement between model averages still leaves considerable uncertainty about a single month's sales.

The dataset ends in December 1994. These 1995 figures illustrate what a planner could have forecast at that point. The accuracy scores above use 1994, where observed sales are available.

## Data

[AustralianWines.csv](AustralianWines.csv) contains one row per calendar month and one sales column per variety. The app reshapes this wide table into a monthly time series for each variety.

| Field after reshaping | Meaning | Example |
| --- | --- | --- |
| Month | Calendar month, parsed from the English month abbreviation and two-digit year | January 1980 |
| Varietal | Series identifier used to group observations and fit models independently | Fortified |
| Sales | Recorded monthly sales in thousand litres | 2,585 represents 2.585 million litres |

There are **180 months × 6 varieties = 1,080 possible sales values**, of which **1,078 are observed**. The importer trims spaces from the CSV headers and standardizes the display names for Sparkling and Rosé. Two Rosé entries, July and August 1994, contain an asterisk.

Missing values receive different treatment according to their role. The history chart leaves a gap. Holdout evaluation uses only months with recorded sales, giving Rosé ten scored months in 1994. If a missing value falls inside a fitting window, the app uses that variety's sales from the same month one year earlier. This preserves the seasonal month and uses information already available at the forecast origin.

## Forecasting methods

| Model | Implementation | What the model learns |
| --- | --- | --- |
| Time series linear model (TSLM) | `TSLM(Sales ~ trend() + season())` | A linear trend and a recurring effect for each month. The estimated December effect is the same size each year on the original sales scale. |
| Exponential smoothing (ETS) | `ETS(Sales)` | A level that updates as observations arrive, with trend and seasonal components where supported. Automatic selection chooses an error, trend, and seasonality specification separately for each variety. |
| Autoregressive integrated moving average (ARIMA) | `ARIMA(Sales)` | Dependence across time in sales or changes in sales. Automatic selection chooses differencing and lag terms, including seasonal terms when appropriate. |

### How evaluation works

The **training cutoff** sets the last month that a model can use for fitting. Every later month inside the selected history window enters the holdout. The app requires at least 36 months of training and at least one later month for a holdout comparison. This chronological split reproduces the information available when the forecast would have been made.

| Measure | What it reports | When it helps |
| --- | --- | --- |
| RMSE | The square root of the average squared error, in thousand litres | Gives large misses extra influence, which matters when a seasonal peak is expensive to miss. |
| MAE | The average absolute error, in thousand litres | Answers “How many litres off was a monthly forecast on average?” Multiply the displayed value by 1,000 to convert to litres. |
| MAPE | The average absolute percentage error over positive observed sales | Expresses error relative to the size of each month's sales. A similar volume error can count more in a low-sales month. |

The app ranks models separately for each variety and gives tied scores the same rank. A model needs a finite prediction for every observed holdout month to receive a score. **Training accuracy** describes errors on the fitted history. **Holdout accuracy** measures performance on later observations. **AICc**, shown beside the model specifications, helps interpret candidate fits within a model family on the same series.

## Using the app

Shiny is an R framework that lets a browser interact with running R code. In this app, the **user interface** defines the controls, tabs, charts, and tables. The **server** reads the selections, fits models, scores predictions, and draws the results. Shiny tracks which outputs depend on each input. Moving the training cutoff changes the fitted models. Switching from RMSE to MAE reuses the predictions and changes the ranking.

### Reproduce the results

1. Open **Sales history** and keep the history window at January 1980–December 1994. The app starts with Fortified and Sparkling. Add the other four varieties for the complete comparison. Each panel has its own vertical scale so smaller series remain visible.
2. Set **Train through** to December 1993 and **Rank models by** to RMSE. Open **Model comparison**. The Fortified ETS row should show an RMSE of **318.90**, and the Rosé rows should show **10 scored months**.
3. Open **Forecasts** and choose **Training cutoff (holdout)**. The black line shows recorded sales and the colored lines show model forecasts. The shaded forecast period overlaps the known 1994 observations, so you can inspect which months produced the largest misses.
4. Switch to **End of selected history (future)** and leave the horizon at 12 months. The models refit through December 1994 and forecast January–December 1995. Select Sparkling and ETS, turn on the 80% interval, and inspect the December row to reproduce the forecast above.
5. Click **Download CSV** to export the selected varieties and models. **About** documents the data treatment and model choices inside the app.

The horizon control applies to future forecasts and supports 1–24 months. The holdout length comes from the gap between the training cutoff and the end of the selected history. To test a different complete year, move **both** the cutoff and the window end. For example, train through December 1992 and end the history in December 1993 to score the 1993 calendar year.

### Read a forecast export

Each exported row represents one combination of variety, month, and model. `Forecast` is the forecast mean. `Actual` contains recorded sales when available and is blank for future months. `Interval (%)`, `Lower`, and `Upper` give the selected prediction level and its bounds. All volume fields use thousand litres. Hiding interval ribbons changes the chart display. The CSV still includes the bounds.

## Running locally

The hosted version opens in a browser. To inspect the R code, modify a model, or run the project locally, download the repository ZIP and extract it, or clone the repository with Git.

```bash
git clone https://github.com/YubiQuinzon/australian-wine-forecasting.git
cd australian-wine-forecasting
```

The deployment manifest records **R 4.5.3** and the package versions used for the hosted build. In a local R session, install the packages once:

```r
install.packages(c(
  "shiny", "dplyr", "tidyr", "ggplot2", "tsibble",
  "fable", "fabletools", "feasts", "distributional", "scales"
))
```

Open `app.R` in RStudio and click **Run App**. Alternatively, start R in the repository directory and run:

```r
shiny::runApp(".")
```

If R reports that it cannot open the CSV, run `file.exists("AustralianWines.csv")` from the app directory. The app reads that exact filename relative to its working directory. If the app asks for more training data, expand the history window or move the cutoff later, leaving at least one month for evaluation. Installing packages from CRAN uses the versions available locally at installation time. For comparisons across environments, check versions against the deployment manifest.

## Repository guide

| File | Role | When to open it |
| --- | --- | --- |
| [app.R](app.R) | Application entry point. Contains data preparation, model fitting, evaluation, plotting, UI, and server logic. | To run the app, inspect a calculation, or change an input or output. |
| [AustralianWines.csv](AustralianWines.csv) | Original monthly sales table read at startup. | To check a recorded value, inspect a missing observation, or reproduce the benchmark. |
| [manifest.json](manifest.json) | Deployment metadata describing the R environment, package dependencies, and bundled files. | To inspect the published environment or troubleshoot a Posit Connect Cloud build. |
| [README.md](README.md) | Project overview, results, and reproduction guide. | To understand the analytical choices and follow a worked example. |

Within `app.R`, `fill_for_fit()` handles missing model inputs, `fit_models()` defines the three candidate models, and `holdout_accuracy()` matches predictions to observations by variety and month. The server's `training_fit` and `future_fit` reactive expressions implement the two forecast origins. These are the relevant places to inspect if a score or a forecast changes after adjusting an input.

### Reproduce the seasonal naive benchmark

The final column of the results table can be checked directly against the CSV with base R. For each month in 1994, use the same month's observed 1993 sales as the forecast. The two years have the same January–December ordering in the source file.

```r
wine <- read.csv("AustralianWines.csv", check.names = FALSE, na.strings = "*")
names(wine) <- trimws(names(wine))
prior <- wine[endsWith(wine$Month, "-93"), ]
test  <- wine[endsWith(wine$Month, "-94"), ]
stopifnot(nrow(test) == 12L, identical(substr(prior$Month, 1, 3),
                                       substr(test$Month, 1, 3)))

errors <- as.matrix(test[, -1]) - as.matrix(prior[, -1])
round(sqrt(colMeans(errors^2, na.rm = TRUE)), 2)
```

## Limitations

The displayed rankings describe one historical forecast origin. A rolling-origin evaluation across several years would show whether the differences persist under other conditions. With one forecast for each horizon in the 1994 experiment, a December error combines December's sales pattern with the difficulty of predicting twelve months ahead.

All three fitted models use the sales history of each variety independently. Price, promotions, inventory, and changes in distribution are outside the dataset. The models can capture recurring December peaks, but the sales series alone cannot establish what caused them. Prediction intervals depend on each fitted model's assumptions and can extend below zero on the original scale. The project is a historical model comparison, and its “future” forecasts are relative to the selected end of history.

**Author** · [Yubi Joy Quinzon](https://github.com/YubiQuinzon)
