library(DBI)
library(RPostgres)

# Reads the connection string you stored in .Renviron
con <- dbConnect(
  RPostgres::Postgres(),
  dbname   = "postgres",
  host     = "aws-0-us-east-1.pooler.supabase.com",  # from your connection string
  port     = 5432,
  user     = "postgres.amjmimrunrpgpwrmmlak",               # from your connection string
  password = Sys.getenv("SUPABASE_DB_PASSWORD")
)

# Simple sanity check: write and read back a tiny test table
dbWriteTable(con, "connection_test", data.frame(status = "it works", ts = Sys.time()), overwrite = TRUE)
print(dbReadTable(con, "connection_test"))

dbDisconnect(con)
