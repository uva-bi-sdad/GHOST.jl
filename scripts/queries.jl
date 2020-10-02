using GHOSS
time_start = GHOSS.now()
setup()
setup_parallel(5)
spdxs = execute(GHOSS.PARALLELENABLER.conn,
                "SELECT spdx FROM gh_2007_2019.licenses ORDER BY spdx;",
                not_null = true) |>
    (obj -> getproperty.(obj, :spdx))
for spdx in spdxs
    queries(spdx)
end
time_end = GHOSS.now()
GHOSS.Dates.canonicalize(GHOSS.Dates.CompoundPeriod(time_end - time_start))
