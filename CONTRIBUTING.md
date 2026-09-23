# Contributing

## Contributions welcome

Bug fixes, improvements, and documentation contributions are welcome.

## Submitting changes

- Keep each pull request focused on a single change. Avoid unrelated cleanup or
  formatting changes.
- Explain what changed and why it is needed. Link any related issue.
- Describe how you tested the change, including the commands you ran, the results
  you observed, and anything you could not test.
- Discuss substantial changes in an issue before starting implementation.

## AI-assisted contributions

AI assistance is welcome. Unreviewed submissions are not.

You are responsible for reviewing and understanding your contribution,
regardless of which tools helped produce it. Do not submit changes you
cannot explain.

Before opening a pull request:

- Read the entire final diff yourself, including changes to tests,
  configuration, dependencies, and documentation.
- Understand what each change does, why it is necessary, and how it
  interacts with existing code. Remove unrelated changes.
- Verify that referenced commands, options, APIs, and dependencies
  actually exist and work with the relevant versions.
- Exercise the affected behavior. Report the commands you ran, the
  results you observed, and anything you could not test. An AI tool
  saying "tests passed" is not a substitute for checking the results.
- Review failure cases and potentially harmful side effects,
  especially privileged commands, file deletion or overwriting,
  downloaded executable code, and changes to system configuration.
- Check for exposed credentials, private information, and third-party
  code whose licensing is incompatible with the project.
- Describe substantial AI assistance in the pull request: what it
  helped with and how you verified the resulting changes.

Be prepared to explain your changes and answer review questions.

## Contribution licensing

Unless you explicitly state otherwise, contributions intentionally submitted for
inclusion in this project are submitted under the Apache License, Version 2.0,
as described in [LICENSE](LICENSE).

Submit only material you have the right to contribute under those terms,
including any necessary permission from an employer or other copyright holder.
Identify third-party material and preserve its required copyright, license, and
attribution notices.

These guidelines describe contribution expectations; they do not modify the
terms of the project's license.

## Review expectations

Maintainers may request changes, additional testing, or an explanation of your
implementation. They may decline contributions, including changes that are not
adequately understood, reviewed, or validated. Submitting a contribution does
not guarantee acceptance.
