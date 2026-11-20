# public API errors keep stable messages

    Code
      aa_settings(admin_role = "owner")
    Condition
      Error in `aa_settings()`:
      ! `admin_role` must be one of the roles in `roles`.

---

    Code
      aa_settings(password_policy = "bad")
    Condition
      Error in `aa_settings()`:
      ! `password_policy` must be one of: "off", "warn", "reject".

---

    Code
      aa_create_user(conn, "worker", "worker-password", "unknown")
    Condition
      Error in `aa_create_user()`:
      ! Invalid role

---

    Code
      aa_create_user(conn, "boss", "worker-password", "user")
    Condition
      Error in `aa_create_user()`:
      ! User already exists

---

    Code
      aa_set_role(conn, "boss", "viewer")
    Condition
      Error in `aa_set_role()`:
      ! You cannot remove the administrator role from the last active administrator

