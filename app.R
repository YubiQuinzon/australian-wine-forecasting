library(shiny)
library(dplyr)
library(tidyr)
library(ggplot2)
library(tsibble)
library(fable)
library(fabletools)
library(feasts)

# The CSV uses English month abbreviations and two-digit years.
raw_wines <- read.csv("AustralianWines.csv", check.names = FALSE,
                      na.strings = "*", strip.white = TRUE)
names(raw_wines) <- trimws(names(raw_wines))
names(raw_wines)[names(raw_wines) == "Rose"] <- "Rosé"
names(raw_wines)[names(raw_wines) == "sparkling"] <- "Sparkling"
varietals <- names(raw_wines)[-1]
raw_wines$Month <- yearmonth(as.Date(sprintf(
  "19%s-%02d-01", substr(raw_wines$Month, 5, 6),
  match(substr(raw_wines$Month, 1, 3), month.abb)
)))
wines <- raw_wines |>
  pivot_longer(-Month, names_to = "Varietal", values_to = "Sales") |>
  as_tsibble(index = Month, key = Varietal)

method_names <- c("TSLM", "ETS", "ARIMA")
method_colors <- c(TSLM = "#17665f", ETS = "#a74f13", ARIMA = "#804473")
min_date <- as.Date(min(wines$Month))
max_date <- as.Date(max(wines$Month))
format_month <- function(x) format(as.Date(x), "%b %Y")

# Fill missing fit inputs with the same calendar month's value a year earlier.
# Apply separately to each fitting window so the holdout cannot leak into training.
fill_for_fit <- function(data) {
  data |>
    group_by(Varietal) |>
    mutate(Sales = coalesce(Sales, lag(Sales, 12))) |>
    ungroup() |>
    as_tsibble(index = Month, key = Varietal)
}

fit_models <- function(data) {
  fill_for_fit(data) |>
    model(
      TSLM = TSLM(Sales ~ trend() + season()),
      ETS = ETS(Sales),
      ARIMA = ARIMA(Sales)
    )
}

holdout_accuracy <- function(predictions, actuals) {
  observed <- as_tibble(actuals) |> select(Varietal, Month, Actual = Sales)
  as_tibble(predictions) |>
    left_join(observed, by = c("Varietal", "Month")) |>
    group_by(Varietal, .model) |>
    summarise(
      Usable = sum(is.finite(Actual) & is.finite(.mean)),
      Observed = sum(is.finite(Actual)),
      RMSE = if (Usable > 0 && Usable == Observed)
        sqrt(mean((Actual - .mean)^2, na.rm = TRUE)) else NA_real_,
      MAE = if (Usable > 0 && Usable == Observed)
        mean(abs(Actual - .mean), na.rm = TRUE) else NA_real_,
      MAPE = if (Usable > 0 && Usable == Observed)
        100 * mean(abs((Actual - .mean)[Actual > 0] / Actual[Actual > 0]),
                   na.rm = TRUE) else NA_real_,
      .groups = "drop"
    )
}

date_plot <- function() {
  list(
    facet_wrap(vars(Varietal), scales = "free_y", ncol = 2),
    scale_x_date(date_labels = "%b %Y", breaks = scales::breaks_pretty(n = 5)),
    scale_y_continuous(labels = scales::label_comma()),
    labs(x = NULL, y = "Sales (thousand litres)"),
    theme_minimal(base_size = 13),
    theme(
      plot.background = element_rect(fill = "white", color = NA),
      legend.position = "bottom",
      panel.grid.minor = element_blank(),
      axis.text.x = element_text(angle = 30, hjust = 1),
      strip.text = element_text(face = "bold"),
      panel.spacing = grid::unit(1, "lines")
    )
  )
}

obs_plot_data <- function(data) {
  as_tibble(data) |>
    group_by(Varietal) |>
    mutate(Date = as.Date(Month), Segment = cumsum(is.na(Sales))) |>
    filter(is.finite(Sales)) |>
    ungroup()
}

historical_plot <- function(data, cutoff) {
  plt <- ggplot(obs_plot_data(data), aes(Date, Sales)) +
    geom_line(aes(group = Segment), color = "#33272b", linewidth = 0.75) +
    date_plot()
  if (cutoff >= min(data$Month) && cutoff <= max(data$Month)) {
    plt <- plt +
      geom_vline(xintercept = as.Date(cutoff), linetype = "dashed", color = "#875766")
  }
  plt
}

forecast_plot <- function(actuals, predictions, origin, show_intervals) {
  history <- obs_plot_data(actuals)
  # Keep three years of context before the forecast origin.
  history <- filter(history, Month >= origin - 35)
  predictions <- filter(predictions, is.finite(.mean))
  last <- as.Date(max(predictions$Month))
  plt <- ggplot() +
    annotate("rect", xmin = as.Date(origin + 1), xmax = last + 15,
             ymin = -Inf, ymax = Inf, fill = "#f5edf0") +
    geom_vline(xintercept = as.Date(origin), linetype = "dashed", color = "#875766")
  if (show_intervals) {
    plt <- plt +
      geom_ribbon(data = predictions, aes(Date, ymin = Lower, ymax = Upper, fill = .model),
                  alpha = 0.13, color = NA, show.legend = FALSE) +
      scale_fill_manual(values = method_colors)
  }
  # Draw actuals over the ribbons.
  plt +
    geom_line(data = history, aes(Date, Sales, group = Segment),
              color = "#33272b", linewidth = 0.8) +
    geom_line(data = predictions, aes(Date, .mean, color = .model), linewidth = 0.9) +
    geom_point(data = predictions, aes(Date, .mean, color = .model), size = 1.25) +
    scale_color_manual(name = "Model", values = method_colors) +
    date_plot()
}

with_intervals <- function(predictions, level) {
  interval <- distributional::hilo(predictions$Sales, level = level)
  as_tibble(predictions) |>
    mutate(Date = as.Date(Month), Lower = interval$lower, Upper = interval$upper)
}

rank_scores <- function(scores, metric) {
  scores |>
    group_by(Varietal) |>
    mutate(Rank = min_rank(.data[[metric]])) |>
    arrange(Varietal, Rank, .model) |>
    ungroup()
}

ui <- fluidPage(
  title = "Australian Wine Sales | Forecast Lab",
  tags$head(tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    tags$style(HTML("
      body {background:#f8f4f1;color:#30252a;font-family:system-ui,-apple-system,sans-serif;}
      .container-fluid {max-width:1480px;padding:0 28px;}
      .hero {background:#44232f;color:#fff8f2;margin:24px 0;border-radius:14px;padding:26px 30px;}
      .hero h1 {font-family:Georgia,serif;font-size:clamp(30px,4vw,48px);margin:0 0 7px;}
      .hero p {color:#f1dbdf;font-size:16px;margin:0;}
      .well,.workspace {background:white;border:1px solid #e9dce0;border-radius:12px;box-shadow:none;}
      .workspace {padding:17px 21px 24px;margin-bottom:25px;}
      .well {padding:19px;}
      .well h2 {font-size:19px;margin:0 0 17px;}
      h2 {font-family:Georgia,serif;font-size:27px;}
      h3 {font-size:19px;font-weight:650;margin-top:22px;}
      a {color:#702e48;}
      .nav-tabs>li>a {color:#66324a;font-weight:650;}
      .nav-tabs>li.active>a {border-top:3px solid #804473;}
      .nav-tabs>li>a:focus-visible, select:focus-visible, input:focus-visible, summary:focus-visible {
        outline:2px solid #804473;outline-offset:2px;
      }
      .note {color:#66565d;margin:10px 0 15px;}
      .context {background:#f3e9ed;border-left:4px solid #804473;padding:11px 14px;margin:18px 0 12px;}
      .table-wrap {overflow-x:auto;}
      .table th {white-space:nowrap;}
      .forecast-values {max-height:440px;overflow:auto;}
      .forecast-values th {position:sticky;top:0;background:white;}
      .btn-default {border-color:#c9b5bf;color:#66324a;}
      details {margin:16px 0;}
      summary {cursor:pointer;font-weight:650;margin-bottom:8px;}
      @media(max-width:767px) {
        .container-fluid {padding:0 15px;}
        .hero {margin-top:12px;padding:17px;}
        .workspace {padding:12px;}
      }
    "))
  ),
  tags$header(class = "hero",
    h1("Australian Wine Sales"),
    p("Compare monthly forecasts across six varietals, 1980–1994.")
  ),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      h2("Analysis settings"),
      selectizeInput("varietals", "Wine varieties", choices = varietals,
                     selected = c("Fortified", "Sparkling"), multiple = TRUE),
      dateRangeInput("window", "History window", start = min_date, end = max_date,
                     min = min_date, max = max_date, format = "M yyyy",
                     startview = "year"),
      dateInput("cutoff", "Train through", value = as.Date("1993-12-01"),
                min = as.Date(min(wines$Month) + 35), max = as.Date(max(wines$Month) - 1),
                format = "M yyyy", startview = "year"),
      p(class = "note", "Dates are treated as whole months. Keep at least 36 months for training and one month for validation."),
      selectInput("metric", "Rank models by", choices = c("RMSE", "MAE", "MAPE")),
      sliderInput("horizon", "Future forecast horizon (months)", min = 1, max = 24,
                  value = 12, step = 1, ticks = FALSE)
    ),
    mainPanel(width = 9, tags$div(class = "workspace",
      tabsetPanel(
        id = "tab",
        tabPanel("Sales history",
          h2("Monthly sales"),
          uiOutput("history_context"),
          uiOutput("history_plot_ui")
        ),
        tabPanel("Model comparison",
          h2("Which model forecasts best?"),
          uiOutput("leader"),
          h3("Holdout accuracy"),
          p(class = "note", "Lower scores are better. RMSE and MAE are in thousand litres. MAPE is a percentage. Scored months count observations with a matching forecast."),
          div(class = "table-wrap", tableOutput("holdout_scores")),
          tags$details(open = "open", tags$summary("Model specifications"),
            p(class = "note", "Specifications are for the training fit. AICc compares candidate fits within a model family on the same series."),
            div(class = "table-wrap", tableOutput("specifications"))
          ),
          tags$details(tags$summary("Training accuracy"),
            p(class = "note", "These scores summarize fitted errors in the training period."),
            div(class = "table-wrap", tableOutput("training_scores"))
          )
        ),
        tabPanel("Forecasts",
          h2("Compare forecast paths"),
          fluidRow(
            column(6, radioButtons("view", "Forecast origin",
                                   c("Training cutoff (holdout)" = "holdout",
                                     "End of selected history (future)" = "future"))),
            column(6, checkboxGroupInput("models", "Show models", method_names,
                                        selected = method_names, inline = TRUE))
          ),
          fluidRow(
            column(6, checkboxInput("intervals", "Show prediction intervals", TRUE)),
            column(6, selectInput("level", "Prediction interval", c("80%" = 80, "95%" = 95),
                                  selected = 80))
          ),
          uiOutput("forecast_context"),
          uiOutput("forecast_plot_ui"),
          h3("Monthly forecast values"),
          p(class = "note", "Forecast and interval bounds are in thousand litres."),
          downloadButton("forecast_csv", "Download CSV"),
          div(class = "table-wrap forecast-values", tableOutput("forecast_values"))
        ),
        tabPanel("About",
          h2("Data and methods"),
          p("The supplied AustralianWines.csv records monthly Australian wine sales from January 1980 through December 1994 in thousand litres."),
          tags$ul(
            tags$li("TSLM is a time series regression with a linear trend and monthly seasonal effects."),
            tags$li("ETS fits exponential smoothing and selects the error, trend and seasonal form."),
            tags$li("ARIMA selects autoregressive, differencing and moving-average terms, including seasonal terms where supported.")
          ),
          h3("Reproduce the comparison"),
          p("Select Fortified and Sparkling and keep the full January 1980–December 1994 history. Train through December 1993 and rank by holdout RMSE. In Forecasts, choose the training cutoff view to check model predictions against 1994 sales. Choose the end-of-history view and a 12-month horizon to forecast 1995."),
          h3("How to read the results"),
          p("Holdout models are fitted through the chosen training month and then predict the remaining months as one block. Future models are fitted again on the entire selected history. Compare models within a variety, since the charts use different y-axis scales."),
          p("The source marks Rosé in July and August 1994 as missing. Charts leave a gap and holdout scores exclude those months. If the missing months are in a fitting window, their training inputs use the same month of the prior year. Model-based intervals are shown on the original scale and may extend below zero.")
        )
      )
    ))
  )
)

server <- function(input, output, session) {
  observeEvent(input$window, {
    req(length(input$window) == 2, all(!is.na(input$window)))
    bounds <- yearmonth(input$window)
    first_cutoff <- bounds[1] + 35
    last_cutoff <- bounds[2] - 1
    if (first_cutoff > last_cutoff) return()
    previous <- yearmonth(input$cutoff)
    if (length(previous) != 1 || is.na(previous) ||
        previous < first_cutoff || previous > last_cutoff) {
      previous <- max(first_cutoff, bounds[2] - 12)
    }
    updateDateInput(session, "cutoff", value = as.Date(previous),
                    min = as.Date(first_cutoff), max = as.Date(last_cutoff))
  }, ignoreInit = TRUE)

  plot_height <- reactive(max(300, 250 * ceiling(length(input$varietals) / 2)))
  history <- reactive({
    validate(need(length(input$varietals), "Select at least one wine variety."),
             need(length(input$window) == 2 && all(!is.na(input$window)),
                  "Choose a start and end month."))
    bounds <- yearmonth(input$window)
    data <- filter(wines, Varietal %in% input$varietals,
                   Month >= bounds[1], Month <= bounds[2])
    validate(need(nrow(data) > 0, "Choose a history window with available sales."))
    data
  })

  cutoff <- reactive({
    validate(need(length(input$cutoff) == 1 && !is.na(input$cutoff),
                  "Choose a training cutoff month."))
    yearmonth(input$cutoff)
  })

  split <- reactive({
    data <- history()
    train <- filter(data, Month <= cutoff())
    validation <- filter(data, Month > cutoff())
    validate(
      need(n_distinct(train$Month) >= 36, "Choose at least 36 months of training history."),
      need(n_distinct(validation$Month) >= 1,
           "Choose a training cutoff before the end of the selected history.")
    )
    list(train = train, validation = validation)
  })

  training_fit <- reactive(fit_models(split()$train))
  holdout <- reactive(forecast(training_fit(), new_data = split()$validation))
  future_fit <- reactive({
    validate(need(n_distinct(history()$Month) >= 36,
                  "Choose at least 36 months of history for future forecasts."))
    fit_models(history())
  })
  future <- reactive(forecast(future_fit(), h = input$horizon))
  scores <- reactive(rank_scores(
    holdout_accuracy(holdout(), split()$validation), input$metric
  ))

  output$history_context <- renderUI({
    data <- history()
    start <- min(data$Month)
    end <- max(data$Month)
    cutoff_text <- if (cutoff() >= start && cutoff() <= end) {
      paste("Dashed line marks", format_month(cutoff()))
    } else {
      "Training cutoff is outside this window"
    }
    p(class = "context",
      sprintf("%s to %s · %s", format_month(start), format_month(end), cutoff_text))
  })

  output$history_plot_ui <- renderUI({
    plotOutput("history_plot", height = paste0(plot_height(), "px"))
  })

  output$history_plot <- renderPlot({
    historical_plot(history(), cutoff())
  }, alt = "Observed monthly wine sales by variety, with a dashed training cutoff.")

  output$leader <- renderUI({
    ranked <- scores()
    leaders <- filter(ranked, Rank == 1)
    data <- split()
    div(class = "context",
        strong(sprintf("Lowest holdout %s by variety", input$metric)),
        p(sprintf("Trained through %s. Evaluated from %s to %s.",
                  format_month(max(data$train$Month)),
                  format_month(min(data$validation$Month)),
                  format_month(max(data$validation$Month)))),
        if (nrow(leaders)) {
          tags$ul(lapply(seq_len(nrow(leaders)), function(i) {
            unit <- if (input$metric == "MAPE") "%" else " thousand litres"
            tags$li(sprintf("%s · %s (%s%s)", leaders$Varietal[i], leaders$.model[i],
                            formatC(leaders[[input$metric]][i], digits = 2,
                                    format = "f", big.mark = ","), unit))
          }))
        },
        if (anyNA(ranked$Rank)) {
          p("A dash indicates a model without a complete set of forecasts for the observed holdout months.")
        })
  })

  output$holdout_scores <- renderTable({
    scores() |>
      transmute(Variety = Varietal, Model = .model, Rank,
                `Scored months` = Usable, `Observed months` = Observed,
                RMSE, MAE, `MAPE (%)` = MAPE)
  }, digits = 2, striped = TRUE, na = "—")

  output$specifications <- renderTable({
    fit <- training_fit()
    specs <- as_tibble(fit) |>
      pivot_longer(all_of(method_names), names_to = "Model", values_to = "Fit") |>
      mutate(Specification = vapply(Fit, format, character(1))) |>
      select(Varietal, Model, Specification)
    criteria <- glance(fit) |>
      as_tibble() |>
      transmute(Varietal, Model = .model, AICc)
    left_join(specs, criteria, by = c("Varietal", "Model")) |>
      arrange(Varietal, match(Model, method_names)) |>
      rename(Variety = Varietal)
  }, digits = 2, striped = TRUE, na = "—")

  output$training_scores <- renderTable({
    accuracy(training_fit()) |>
      as_tibble() |>
      transmute(Variety = Varietal, Model = .model, RMSE, MAE, `MAPE (%)` = MAPE)
  }, digits = 2, striped = TRUE, na = "—")

  active_forecasts <- reactive({
    req(input$view)
    validate(need(length(input$models), "Select at least one forecast model."))
    raw <- if (input$view == "holdout") holdout() else future()
    with_intervals(filter(raw, .model %in% input$models), as.numeric(input$level))
  })

  output$forecast_context <- renderUI({
    pred <- active_forecasts()
    context <- if (input$view == "holdout") {
      "Black lines show recorded sales. Shading marks the holdout used to score the models."
    } else {
      "Models are refitted on the full selected history. Shading marks months after that history."
    }
    p(class = "context",
      sprintf("%s to %s. %s", format_month(min(pred$Month)),
              format_month(max(pred$Month)), context))
  })

  output$forecast_plot_ui <- renderUI({
    plotOutput("forecast_plot", height = paste0(plot_height(), "px"))
  })

  output$forecast_plot <- renderPlot({
    pred <- active_forecasts()
    validate(need(any(is.finite(pred$.mean)), "No forecasts are available for these selections."))
    data <- history()
    origin <- if (input$view == "holdout") cutoff() else max(data$Month)
    forecast_plot(data, pred, origin, input$intervals)
  }, alt = "Actual wine sales and model forecasts by variety, with optional prediction intervals.")

  forecast_values <- reactive({
    actuals <- as_tibble(history()) |> select(Varietal, Month, Actual = Sales)
    active_forecasts() |>
      left_join(actuals, by = c("Varietal", "Month")) |>
      arrange(Varietal, Month, match(.model, method_names)) |>
      transmute(Variety = Varietal, Month = format(Date, "%Y-%m"),
                Model = .model, Actual, Forecast = .mean,
                `Interval (%)` = as.numeric(input$level), Lower, Upper)
  })

  output$forecast_values <- renderTable({
    results <- forecast_values()
    if (input$view == "future") select(results, -Actual) else results
  }, digits = 1, striped = TRUE, na = "—")

  output$forecast_csv <- downloadHandler(
    filename = function() paste0("wine-", input$view, "-forecasts.csv"),
    content = function(file) write.csv(forecast_values(), file, row.names = FALSE, na = "")
  )
}

shinyApp(ui, server)
