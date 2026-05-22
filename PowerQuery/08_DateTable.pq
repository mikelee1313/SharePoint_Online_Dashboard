// ============================================================
// 08_DateTable.pq
// Calculated Date Dimension Table
// No external data source – generated within Power Query
// 
// Covers: from Jan 1 two years ago to Dec 31 of current year
// ============================================================

let
    // ── Define date range ─────────────────────────────────────────────────────
    StartDate = #date(Date.Year(Date.From(DateTime.LocalNow())) - 2, 1, 1),
    EndDate   = #date(Date.Year(Date.From(DateTime.LocalNow())) + 1, 12, 31),

    // ── Generate date list ────────────────────────────────────────────────────
    DayCount  = Duration.Days(EndDate - StartDate) + 1,
    DateList  = List.Dates(StartDate, DayCount, #duration(1, 0, 0, 0)),
    AsTable   = Table.FromList(DateList, Splitter.SplitByNothing(), {"Date"}),
    TypedDate = Table.TransformColumnTypes(AsTable, {{"Date", type date}}),

    // ── Add calendar attributes ───────────────────────────────────────────────
    withYear       = Table.AddColumn(TypedDate,  "Year",
                         each Date.Year([Date]),   Int64.Type),
    withQuarterNum = Table.AddColumn(withYear,   "QuarterNumber",
                         each Date.QuarterOfYear([Date]), Int64.Type),
    withQuarter    = Table.AddColumn(withQuarterNum, "Quarter",
                         each "Q" & Number.ToText([QuarterNumber]), type text),
    withYearQ      = Table.AddColumn(withQuarter, "YearQuarter",
                         each Number.ToText([Year]) & " Q" & Number.ToText([QuarterNumber]),
                         type text),
    withMonthNum   = Table.AddColumn(withYearQ,  "MonthNumber",
                         each Date.Month([Date]), Int64.Type),
    withMonthName  = Table.AddColumn(withMonthNum, "MonthName",
                         each Date.ToText([Date], "MMMM"), type text),
    withMonthShort = Table.AddColumn(withMonthName, "MonthShort",
                         each Date.ToText([Date], "MMM"), type text),
    withYearMonth  = Table.AddColumn(withMonthShort, "YearMonth",
                         each Number.ToText([Year]) & "-"
                              & Text.PadStart(Number.ToText([MonthNumber]), 2, "0"),
                         type text),
    withWeekNum    = Table.AddColumn(withYearMonth, "WeekNumber",
                         each Date.WeekOfYear([Date]), Int64.Type),
    withDayNum     = Table.AddColumn(withWeekNum,  "DayOfMonthNumber",
                         each Date.Day([Date]), Int64.Type),
    withDayOfWeek  = Table.AddColumn(withDayNum,   "DayOfWeekNumber",
                         each Date.DayOfWeek([Date], Day.Monday) + 1, Int64.Type),
    withDayName    = Table.AddColumn(withDayOfWeek, "DayName",
                         each Date.ToText([Date], "dddd"), type text),
    withDayShort   = Table.AddColumn(withDayName,  "DayShort",
                         each Date.ToText([Date], "ddd"), type text),
    withIsWeekend  = Table.AddColumn(withDayShort, "IsWeekend",
                         each Date.DayOfWeek([Date]) = Day.Saturday
                           or Date.DayOfWeek([Date]) = Day.Sunday,
                         type logical),
    withIsWeekday  = Table.AddColumn(withIsWeekend, "IsWeekday",
                         each not [IsWeekend], type logical),

    // ── Rolling period flags ──────────────────────────────────────────────────
    Today          = Date.From(DateTime.LocalNow()),
    withIsLast7    = Table.AddColumn(withIsWeekday, "IsLast7Days",
                         each [Date] >= Date.AddDays(Today, -7) and [Date] <= Today,
                         type logical),
    withIsLast30   = Table.AddColumn(withIsLast7,   "IsLast30Days",
                         each [Date] >= Date.AddDays(Today, -30) and [Date] <= Today,
                         type logical),
    withIsLast90   = Table.AddColumn(withIsLast30,  "IsLast90Days",
                         each [Date] >= Date.AddDays(Today, -90) and [Date] <= Today,
                         type logical),
    withIsCurrentM = Table.AddColumn(withIsLast90,  "IsCurrentMonth",
                         each Date.Month([Date]) = Date.Month(Today)
                           and Date.Year([Date]) = Date.Year(Today),
                         type logical),
    withIsCurrentY = Table.AddColumn(withIsCurrentM, "IsCurrentYear",
                         each Date.Year([Date]) = Date.Year(Today),
                         type logical),

    // ── DateKey integer (YYYYMMDD) for optional integer relationships ─────────
    withDateKey    = Table.AddColumn(withIsCurrentY, "DateKey",
                         each Date.Year([Date]) * 10000
                           + Date.Month([Date]) * 100
                           + Date.Day([Date]),
                         Int64.Type),

    // ── Final column order ─────────────────────────────────────────────────────
    result = Table.ReorderColumns(withDateKey, {
        "Date", "DateKey",
        "Year", "YearQuarter", "Quarter", "QuarterNumber",
        "YearMonth", "MonthName", "MonthShort", "MonthNumber",
        "WeekNumber",
        "DayName", "DayShort", "DayOfMonthNumber", "DayOfWeekNumber",
        "IsWeekend", "IsWeekday",
        "IsLast7Days", "IsLast30Days", "IsLast90Days",
        "IsCurrentMonth", "IsCurrentYear"
    }, MissingField.Ignore)

in
    result
