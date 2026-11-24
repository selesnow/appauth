# appauth reference: AI agent skills

Package version: 0.13.0. This file is generated automatically from the package help (`dev/skills/build_reference.R`) and must not be edited by hand.

Functions in this section:
`aa_install_skills()`

## Contents

- [aa_install_skills](#aa_install_skills)

## aa_install_skills

```text
Install skills for AI agents

Description:

     The package ships two skills for AI agents (Claude Code, Codex and others), written
     in English: 'appauth' (function reference, database schema, events, interface
     identifiers) and 'appauth-secure-shiny' (adopting 'appauth', migrating hand-written
     authentication, security audit of an application). The function copies them from the
     installed package into the skills directory of a project or of the user.

Usage:

     aa_install_skills(
       path = NULL,
       agent = c("claude", "agents"),
       global = FALSE,
       overwrite = FALSE
     )

Arguments:

    path: Directory to copy to. Computed from 'agent' by default.

   agent: Which agent to copy for: '"claude"' ('.claude/skills', Claude Code) or
          '"agents"' ('.agents/skills', Codex, Posit Assistant and others). Ignored if
          'path' is set.

  global: Copy to the user's home directory ('~') rather than to the current project.

overwrite: Overwrite skills that are already installed (for example, after a package
          update).

Value:

     An invisible vector of paths to the installed skills.

Examples:

     ## Not run:

     # into the current project for Claude Code
     aa_install_skills()

     # for Codex and Posit Assistant, overwriting after a package update
     aa_install_skills(agent = "agents", overwrite = TRUE)
     ## End(Not run)
```

