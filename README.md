# Australian Wine Sales

A Shiny for R app for comparing monthly forecasts across six Australian wine varieties. It includes the original assignment CSV.

## Run locally

1. Extract the ZIP and keep `app.R` and `AustralianWines.csv` in the same directory.
2. From the R console, install the app's dependencies once:

   ```r
   install.packages(c("shiny", "dplyr", "tidyr", "ggplot2", "tsibble",
                      "fable", "fabletools", "feasts", "distributional", "scales"))
   ```

3. Open `app.R` in RStudio and click **Run App**, or use this command with the path to the extracted app folder:

   ```r
   shiny::runApp("AustralianWineShiny")
   ```

## Reproduce the data story

The defaults select Fortified and Sparkling, with January 1980–December 1994 history and a December 1993 training cutoff. In **Model comparison**, read the 1994 holdout scores. In **Forecasts**, keep **Training cutoff (holdout)** to compare against 1994 observed sales. Switch to **End of selected history (future)** with a 12-month horizon to see the refitted models' 1995 forecasts. Toggle model lines and interval ribbons, or download the monthly estimates and bounds.

## Submit

The course template calls for a deployed Shiny URL and an instructor-accessible code URL (GitHub or Posit Cloud). The app folder can be published from RStudio after connecting your Posit hosting account. For a GitHub-backed Connect Cloud deployment, push this folder, including the supplied `manifest.json`, to your repository and select `app.R` as the primary file. Enter both URLs in Part I of the submission document. Confirm the instructor can open them before submitting.

[Posit Connect Cloud deployment guide](https://docs.posit.co/connect-cloud/how-to/r/shiny-r.html)
