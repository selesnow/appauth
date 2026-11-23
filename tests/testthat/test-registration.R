# Self-registration: pending accounts, email confirmation and rate limits.

reg_box <- function(env = parent.frame()) {
  box <- new.env(parent = emptyenv())
  box$sent <- list()
  box
}

reg_settings <- function(box, ..., verify = TRUE) {
  args <- list(
    registration_enabled = TRUE,
    registration_verify_email = verify,
    reset_base_url = "https://apps.example.com/my_app",
    send_reset = function(email, link, login) {
      box$sent[[length(box$sent) + 1]] <- list(
        email = email,
        link = link,
        login = login
      )
    },
    registration_role = "viewer"
  )
  do.call(aa_settings, utils::modifyList(args, list(...)))
}

reg_token <- function(link) {
  sub("^.*register=", "", link)
}

reg_db <- function(env = parent.frame()) {
  con <- new_db(env)
  aa_init_db(con)
  aa_create_first_admin(con, "boss", "boss-password")
  con
}

test_that("registration is disabled by default", {
  con <- reg_db()
  result <- aa_register_user(con, "worker", "worker-password", "worker@example.com")

  expect_false(result$sent)
  expect_identical(result$reason, "disabled")
  expect_identical(nrow(aa_query(con, "SELECT login FROM users")), 1L)
})

test_that("without email confirmation the account is created immediately", {
  con <- reg_db()
  box <- reg_box()
  settings <- reg_settings(box, verify = FALSE)

  result <- aa_register_user(
    con, "worker", "worker-password", "worker@example.com", settings
  )

  expect_true(result$sent)
  expect_identical(result$reason, "created")
  expect_identical(result$login, "worker")
  expect_length(box$sent, 0)
  expect_identical(
    aa_query(con, "SELECT email, role FROM users WHERE login = ?",
             params = list("worker"))$email,
    "worker@example.com"
  )
  expect_identical(
    aa_query(con, "SELECT role FROM users WHERE login = ?",
             params = list("worker"))$role,
    "viewer"
  )
  expect_false(is.null(aa_authenticate(con, "worker", "worker-password")))
  expect_identical(
    aa_query(con, "SELECT used FROM registrations")$used,
    1L
  )
})

test_that("with email confirmation only the hash and the token hash are stored", {
  con <- reg_db()
  box <- reg_box()
  settings <- reg_settings(box)

  result <- aa_register_user(
    con, "worker", "worker-password", "worker@example.com", settings
  )

  expect_true(result$sent)
  expect_identical(result$reason, "sent")
  expect_length(box$sent, 1)
  expect_identical(box$sent[[1]]$login, "worker")
  expect_identical(box$sent[[1]]$email, "worker@example.com")

  token <- reg_token(box$sent[[1]]$link)
  expect_true(grepl("register=", box$sent[[1]]$link, fixed = TRUE))
  expect_identical(aa_registration_token_login(con, token), "worker")

  pending <- aa_query(con, "SELECT * FROM registrations")
  expect_identical(nrow(pending), 1L)
  expect_false(any(as.character(unlist(pending)) %in% c(token, "worker-password")))
  expect_true(aa_is_password_hash(pending$password[1]))
  expect_identical(pending$token_hash[1], aa_token_hash(token))
})

test_that("the confirmation link creates the account only once", {
  con <- reg_db()
  box <- reg_box()
  settings <- reg_settings(box)
  aa_register_user(con, "worker", "worker-password", "worker@example.com", settings)
  token <- reg_token(box$sent[[1]]$link)

  expect_identical(aa_confirm_registration(con, token, settings), "worker")
  expect_false(is.null(aa_get_user(con, "worker")))
  expect_true(aa_verify_password(
    "worker-password",
    aa_query(con, "SELECT password FROM users WHERE login = ?",
             params = list("worker"))$password
  ))
  expect_error(
    aa_confirm_registration(con, token, settings),
    class = "appauth_error_user"
  )
  expect_null(aa_registration_token_login(con, token))
  expect_null(aa_registration_token_login(con, "not-a-token"))
})

test_that("a taken login or address is not revealed to the visitor", {
  con <- reg_db()
  box <- reg_box()
  settings <- reg_settings(box)
  aa_set_email(con, "boss", "boss@example.com")

  expect_identical(
    aa_register_user(con, "boss", "worker-password", "new@example.com",
                     settings)$reason,
    "user_exists"
  )
  expect_identical(
    aa_register_user(con, "worker", "worker-password", "boss@example.com",
                     settings)$reason,
    "email_exists"
  )
  expect_identical(
    aa_register_user(con, "worker", "worker-password", "BOSS@example.com",
                     settings)$reason,
    "email_exists"
  )
  expect_length(box$sent, 0)
  expect_identical(nrow(aa_query(con, "SELECT login FROM registrations")), 0L)
})

test_that("pending registrations reserve a login and an address", {
  con <- reg_db()
  box <- reg_box()
  settings <- reg_settings(box)
  aa_register_user(con, "worker", "worker-password", "worker@example.com", settings)

  expect_identical(
    aa_register_user(con, "WORKER", "worker-password", "other@example.com",
                     settings)$reason,
    "user_exists"
  )
  expect_identical(
    aa_register_user(con, "other", "worker-password", "worker@example.com",
                     settings)$reason,
    "email_exists"
  )
  expect_identical(nrow(aa_query(con, "SELECT login FROM registrations")), 1L)
})

test_that("a domain list restricts registration addresses", {
  con <- reg_db()
  box <- reg_box()
  settings <- reg_settings(box, registration_domains = "example.com")

  expect_identical(
    aa_register_user(con, "worker", "worker-password", "worker@example.com",
                     settings)$reason,
    "sent"
  )
  expect_identical(
    aa_register_user(con, "other", "worker-password", "other@outside.test",
                     settings)$reason,
    "registration_domain"
  )
  expect_equal(
    aa_registration_domain_problem("worker@Example.COM", settings),
    NULL
  )
})

test_that("hourly limit counts pending registrations", {
  con <- reg_db()
  box <- reg_box()
  settings <- reg_settings(box, registration_max_per_hour = 1)

  expect_identical(
    aa_register_user(con, "one", "worker-password", "one@example.com",
                     settings)$reason,
    "sent"
  )
  expect_identical(
    aa_register_user(con, "two", "worker-password", "two@example.com",
                     settings)$reason,
    "registration_throttled"
  )
})

test_that("a failing email sender consumes the token", {
  con <- reg_db()
  settings <- aa_settings(
    registration_enabled = TRUE,
    reset_base_url = "https://apps.example.com/my_app",
    send_reset = function(email, link, login) stop("mail is down")
  )

  expect_message(
    result <- aa_register_user(
      con, "worker", "worker-password", "worker@example.com", settings
    ),
    "mail is down"
  )
  expect_identical(result$reason, "send_failed")
  expect_identical(nrow(aa_query(con, "SELECT login FROM registrations WHERE used = 0")), 0L)
})

test_that("creating the same user elsewhere invalidates a pending registration", {
  con <- reg_db()
  box <- reg_box()
  settings <- reg_settings(box)
  aa_register_user(con, "worker", "worker-password", "worker@example.com", settings)
  token <- reg_token(box$sent[[1]]$link)

  aa_create_user(
    con, "worker", "another-password", "viewer",
    email = "worker@example.com"
  )

  expect_null(aa_registration_token_login(con, token))
  expect_error(
    aa_confirm_registration(con, token, settings),
    class = "appauth_error_user"
  )
  expect_identical(
    nrow(aa_query(con, "SELECT login FROM users WHERE login = 'worker'")),
    1L
  )
})

test_that("the confirmation link supports an application address with a query", {
  settings <- aa_settings(
    reset_base_url = "https://apps.example.com/my_app?lang=en"
  )

  expect_identical(
    aa_registration_link(settings, "T"),
    "https://apps.example.com/my_app?lang=en&register=T"
  )
})
