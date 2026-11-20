test_that("public API errors keep stable messages", {
  conn <- users_db()
  aa_create_first_admin(conn, "boss", "boss-password")

  expect_snapshot(error = TRUE, aa_settings(admin_role = "owner"))
  expect_snapshot(error = TRUE, aa_settings(password_policy = "bad"))
  expect_snapshot(
    error = TRUE,
    aa_create_user(conn, "worker", "worker-password", "unknown")
  )
  expect_snapshot(
    error = TRUE,
    aa_create_user(conn, "boss", "worker-password", "user")
  )
  expect_snapshot(error = TRUE, aa_set_role(conn, "boss", "viewer"))

  DBI::dbDisconnect(conn)
})
