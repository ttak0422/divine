# Contributing to divine

These conventions apply to human contributors and coding agents. Keep changes
focused and use the repository templates, including when posting through a CLI
or API.

## Language

Use English for issues, commit messages, pull requests, documentation, code
comments, help and diagnostics, and test descriptions. Preserve intentional
language-specific test data or quotations with an English explanation.
Translation must not change behavior, requirements, or decision status.

## Issues

Search existing issues and pull requests before opening a new one. Use a short,
descriptive English title and the appropriate template:

- [Bug report](.github/ISSUE_TEMPLATE/bug_report.yml): reproduction, expected and
  actual behavior, and the relevant environment.
- [Change proposal](.github/ISSUE_TEMPLATE/change_proposal.yml): the problem,
  desired outcome, scope, and a way to verify completion. This also covers
  documentation, maintenance, and design work.

Separate observed facts, proposed solutions, and open questions. A proposal does
not become an accepted design decision merely because an issue or PR exists.
Do not include secrets or private machine details in reports or logs.

## Commit messages

Use the format and types in [.gitmessage](.gitmessage):

```text
<type>(<scope>): <short summary>
```

The summary is in the present tense, starts in lowercase, and has no trailing
period. Use a concise scope describing the affected area; there is no fixed scope
registry. For example:

```text
docs(contributing): define contribution formats
```

Add a body when needed to explain the reason for the change. Separate it from the
subject with a blank line. Use `BREAKING CHANGE: <summary>` and
`DEPRECATED: <description>` footer paragraphs when applicable, separated from the
body by a blank line. Do not leave template placeholders in the final message.

The template is copied unchanged from
[ttak0422/dotfiles at 3cbe677](https://github.com/ttak0422/dotfiles/blob/3cbe677f76dee4e1fd02dd0676ecc402ffd99c91/git/committemplate).
To enable it for this checkout only, run from the repository root:

```sh
git config --local commit.template .gitmessage
```

The template is a writing aid, not a commit hook. Apply the same format when using
`git commit -m`, a GUI, or an agent that supplies messages directly.

## Pull requests

Use the commit subject format for the PR title. Fill out the
[PR template](.github/pull_request_template.md), retaining its headings and using
`None` or `Not run: <reason>` where appropriate:

- **Purpose:** why the change is needed.
- **Changes:** the meaningful changes and boundaries of the work.
- **Validation:** exact commands and results, relevant platform or versions, and
  checks not run. Distinguish evaluation from executed tests and fixture coverage
  from broader compatibility claims.
- **Related issues and dependencies:** links and any required merge order. Use
  closing keywords only when the PR fully resolves an issue.
- **Open questions and limitations:** unresolved decisions, known gaps, and
  follow-up work. Use `None` when there are none.

Read the relevant documentation and run the applicable checks available on the
branch. Do not invent test commands or claim checks passed without running them.
For documentation-only changes, check links, template syntax, and whitespace as
applicable. If a PR is intended to merge independently, base it on the target
branch without unrelated implementation commits.

When squash-merging, use the same commit format for the final subject and review
the generated body so template instructions and obsolete checklists do not enter
the commit history.
