# Catalog of authorization events

The package reports events to the
`on_event(event, user, session_id, value)` hook defined by the
application (writing to a log, a messenger notification, etc.). This
function returns the full list of events the package can send.

## Usage

``` r
aa_events(lang = c("en", "ru"))
```

## Arguments

- lang:

  Language of the `description` and `value` columns: `"en"` (default) or
  `"ru"`.

## Value

A data frame with columns `event` (key), `description` (what happened)
and `value` (what is in the `value` field).

## Details

The `user` field in the hook is the login on whose behalf the event
happens (for a failed sign-in it is the entered login, and if there is
no login, `"anonymous"`), and `value` holds the detail described in the
`value` column. Passwords and tokens never appear in events.

## Examples

``` r
aa_events()
#>                       event
#> 1             login_success
#> 2              login_failed
#> 3              login_locked
#> 4        login_blocked_user
#> 5           login_throttled
#> 6            login_unlocked
#> 7                    logout
#> 8     session_forced_logout
#> 9       first_admin_created
#> 10               user_added
#> 11             user_removed
#> 12        user_role_changed
#> 13         password_changed
#> 14         sessions_revoked
#> 15           password_reset
#> 16             user_blocked
#> 17           user_unblocked
#> 18            access_denied
#> 19 password_reset_requested
#> 20      password_reset_done
#> 21    password_reset_failed
#> 22            email_changed
#> 23             totp_enabled
#> 24            totp_disabled
#> 25              totp_failed
#> 26               totp_reset
#> 27       recovery_code_used
#> 28      google_login_failed
#> 29        weak_password_set
#> 30   registration_requested
#> 31   registration_confirmed
#> 32      registration_failed
#> 33      google_user_created
#>                                                                      description
#> 1     Successful sign-in (by password, with Google or by an auto sign-in cookie)
#> 2                                                    Incorrect login or password
#> 3                       Sign-in attempt for a login locked after failed attempts
#> 4                          Sign-in attempt by a user blocked by an administrator
#> 5            Rejected because of the overall per-minute limit of failed attempts
#> 6                             An administrator removed the sign-in attempts lock
#> 7                                               The user signed out on their own
#> 8                                                 The session was ended forcibly
#> 9                                            The first administrator was created
#> 10                                                 An administrator added a user
#> 11                                               An administrator deleted a user
#> 12                                        An administrator changed a user's role
#> 13                                           The user changed their own password
#> 14                                 An administrator ended all sessions of a user
#> 15                                    An administrator changed a user's password
#> 16                                               An administrator blocked a user
#> 17                                             An administrator unblocked a user
#> 18                         Access denied: the role lacks the required permission
#> 19 Password recovery requested by email (the user always gets the same response)
#> 20                                Password changed using the link from the email
#> 21                                     Invalid or expired password recovery link
#> 22                       An administrator set, changed or removed a user's email
#> 23                                    The user enabled two-factor authentication
#> 24                                   The user disabled two-factor authentication
#> 25                       Incorrect code when confirming sign-in or disabling 2FA
#> 26                                           An administrator reset a user's 2FA
#> 27                                        Sign-in confirmed with a recovery code
#> 28                      Failed Google sign-in (the user is shown a generic text)
#> 29                  A weak password was accepted (password_policy = "warn" mode)
#> 30              Self-registration requested (the user is shown a generic answer)
#> 31                              Account created from the email confirmation link
#> 32                                      Failed attempt to confirm a registration
#> 33                         Account created automatically on first Google sign-in
#>                                                                                                                                                                                                                   value
#> 1                                                                                                                                    cookie (auto sign-in), google (Google sign-in) or registration (self-registration)
#> 2                                                                                                                                                                     password_disabled if password sign-in is disabled
#> 3                                                                                                                                                                                           seconds until the lock ends
#> 4                                                                                                                                                                                                                      
#> 5                                                                                                                                                                                                                      
#> 6                                                                                                                                                                                       login the lock was removed from
#> 7                                                                                                                                                                                                                      
#> 8                                                                                                                                                                 reason: deleted, blocked, role_changed, token_revoked
#> 9                                                                                                                                                                                                                      
#> 10                                                                                                                                                                                   login of the new user and the role
#> 11                                                                                                                                                                                            login of the deleted user
#> 12                                                                                                                                                                                               login and the new role
#> 13                                                                                                                                                                                                                     
#> 14                                                                                                                                                                                                           user login
#> 15                                                                                                                                                                                                           user login
#> 16                                                                                                                                                                                                           user login
#> 17                                                                                                                                                                                                           user login
#> 18                                                                                                                                                                                                      permission name
#> 19                                                                                                                                                     result: sent, no_user, no_email, blocked, throttled, send_failed
#> 20                                                                                                                                                                                                                     
#> 21                                                                                                                                                                                                                     
#> 22                                                                                                                                                                                                           user login
#> 23                                                                                                                                                                                                                     
#> 24                                                                                                                                                                                                                     
#> 25                                                                                                                                                                                                                     
#> 26                                                                                                                                                                                                           user login
#> 27                                                                                                                                                                                                                     
#> 28 reason: start_failed, bad_state, bad_browser, bad_code, exchange_failed, bad_token, bad_nonce, email_unverified, domain, no_user, blocked, cancelled, signup_login_taken; followed by a space and the email if known
#> 29                                                                                                                                          login and reason: password_common, password_equals_login, password_repeated
#> 30                                                   reason: sent, created, user_exists, email_exists, email_invalid, registration_domain, registration_throttled, send_failed or a login or password validation reason
#> 31                                                                                                                                                                                                login of the new user
#> 32                                                                                                                                                         reason: registration_link_invalid, user_exists, email_exists
#> 33                                                                                                                                                                                                login of the new user
aa_events()$event
#>  [1] "login_success"            "login_failed"            
#>  [3] "login_locked"             "login_blocked_user"      
#>  [5] "login_throttled"          "login_unlocked"          
#>  [7] "logout"                   "session_forced_logout"   
#>  [9] "first_admin_created"      "user_added"              
#> [11] "user_removed"             "user_role_changed"       
#> [13] "password_changed"         "sessions_revoked"        
#> [15] "password_reset"           "user_blocked"            
#> [17] "user_unblocked"           "access_denied"           
#> [19] "password_reset_requested" "password_reset_done"     
#> [21] "password_reset_failed"    "email_changed"           
#> [23] "totp_enabled"             "totp_disabled"           
#> [25] "totp_failed"              "totp_reset"              
#> [27] "recovery_code_used"       "google_login_failed"     
#> [29] "weak_password_set"        "registration_requested"  
#> [31] "registration_confirmed"   "registration_failed"     
#> [33] "google_user_created"     
```
