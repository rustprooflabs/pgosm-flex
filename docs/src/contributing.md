# Contributing

Thank you for your interest in contributing to PgOSM Flex!

All types of contributions are encouraged and valued. This page outlines
different ways you can contribute with details about how this project handles them.
Please make sure to read the relevant sections below before making your contribution.
This makes it much easier for maintainers and smooths out the experience for
everyone involved.

The PgOSM Flex community looks forward to your contributions. 🎉


> If you like the project, but do not have time to contribute directly, that is fine.
> There are other easy ways to support the project and show your appreciation,
> which we would also be very happy about:
> - Star the [project on GitHub](https://github.com/rustprooflabs/pgosm-flex).
> - Blog or otherwise post about it on the social media of your choice.
> - Refer to this project in your project's readme.
> - Tell your friends / colleagues.
> - Mention the project at local meetups. 



## Code of Conduct

This project and everyone participating in it is governed by the
[Code of Conduct](code-of-conduct.md).
By participating, you are expected to uphold this code.
Please report unacceptable behavior to [the maintainers](mailto:support@rustprooflabs.com).

## Ways to Contribute

The PgOSM Flex project is managed on GitHub.  GitHub provides multiple ways to
interact with and contribute to this project, including
[discussions](https://github.com/rustprooflabs/pgosm-flex/discussions/),
[issues](https://github.com/rustprooflabs/pgosm-flex/issues),
and [pull requests (PRs)](https://github.com/rustprooflabs/pgosm-flex/pulls).
A GitHub account is required for many interactions with the community, such as
creating issues, leaving comments, and many other actions available through GitHub.
The following sections explain various ways to use these GitHub features to
contribute and otherwise interact with the community.

### Discussions: Questions, Ideas, Show & Tell

Before asking a question, search for existing
[discussions](https://github.com/rustprooflabs/pgosm-flex/discussions)
and [issues](https://github.com/rustprooflabs/pgosm-flex/issues)
that might address your question.
If you find a suitable item yet still need clarification,
write your question as a comment on the existing item to keep the discussion in
a consolidated location.
It is also advisable to search this documentation and the internet for answers first.

If your question is not already being addressed, start a new
[Discussion](https://github.com/rustprooflabs/pgosm-flex/discussions/new/choose)
with as much context and detail as possible.
GitHub provides discussion types for
[Q & A](https://github.com/rustprooflabs/pgosm-flex/discussions/new?category=q-a),
[Discussions](https://github.com/rustprooflabs/pgosm-flex/discussions/new?category=ideas),
[Show and Tell](https://github.com/rustprooflabs/pgosm-flex/discussions/new?category=show-and-tell)
and more.  If a question turns into the discovery of a bug or feature request,
Discussions can be converted into issues.


#### List Your Project

The PgOSM Flex project encourages you to [list your project](/projects.md)
using PgOSM Flex. The easiest way to start this is to open a
[Show and Tell](https://github.com/rustprooflabs/pgosm-flex/discussions/new?category=show-and-tell)
discussion.  Explain how PgOSM Flex is used in your project, if you have a blog post
or other easy ways to show this, make sure to add links!

### Issues: Enhancements and Bugs

This section guides you through submitting GitHub issues for PgOSM Flex. Issues
are used to suggest completely new features, minor improvements, and report bugs. 

Following these guidelines will help maintainers and the community understand
your suggestion and make PgOSM Flex as useful and bug-free as possible.


#### Before Submitting an Issue

- Make sure that you are using the latest version.
- Read the [documentation](/index.html) to see if your topic is already covered
- Search [existing isues](https://github.com/rustprooflabs/pgosm-flex/issues) to see if there is already an open issue on the topic. If there is an existing issue, add a comment there instead of opening a new issue.
- Find out whether your idea fits with the scope and [aims of the project](index.html#project-goals). It's up to you to make a strong case to convince the project's developers of the merits of this feature. Keep in mind that we want features that will be useful to the majority of our users and not just a small subset. If you're just targeting a minority of users, consider writing an add-on/plugin library.


#### Feature Request

Feature requests are tracked as
[GitHub issues](https://github.com/rustprooflabs/pgosm-flex/issues).

- Use a **clear and descriptive title** for the issue to identify the suggestion.
- Provide a **step-by-step description of the suggested enhancement** in as many details as possible.
- **Describe the current behavior** and **explain which behavior you expected to see instead** and why. At this point you can also tell which alternatives do not work for you.
- **Explain why this enhancement would be useful** to PgOSM Flex users.



#### Bug Report

A bug report indicates PgOSM Flex is not working as advertised or expected.
Use the [bug report template](https://github.com/rustprooflabs/pgosm-flex/issues/new?assignees=&labels=&projects=&template=bug_report.md&title=) to submit your issue.  Fill in
detailed information for as many of the sections as possible.

The bug report template includes a series of headers
(defined as lines starting with `#` symbols) with comments prompting you for input.
Use the "Write" and "Preview" tabs in the GitHub interface to edit and preview your issue.


- Make sure that you are using the latest version.
- Make sure that you have read the [documentation](/index.html).
- Determine if your bug is really a bug and not an error on your side e.g. using incompatible environment components/versions.
- To see if other users have experienced (and potentially already solved) the same issue you are having, check if there is not already a bug report existing for your bug or error in the [issues](https://github.com/rustprooflabs/pgosm-flex/issues).


#### Security Advisory

Security related concerns should be submitted using GitHub's
[Security Advisory](https://github.com/rustprooflabs/pgosm-flex/security/advisories/new)
feature.  This provides a secure method to communicate with project maintainers.

RustProof Labs makes security a top priority and will address any security concerns
as quickly as possible.



#### Once it's submitted

After you have submitted an issue, the project team will label the issue accordingly.
Maintainers will try to reproduce the issue with your provided steps. If there are no reproduction steps or no obvious way to reproduce the issue, the team will ask you for more details.



### Improving Documentation

See the `README.md` in the [`pgosm-flex/docs` directory](https://github.com/rustprooflabs/pgosm-flex/tree/main/docs).




## Submitting Pull Requests

This project uses Pull Requests (PRs) like so many other open source projects.
Fork the project into your own repository, create a feature branch there,
and make one or more pull requests back to the main PgOSM Flex repository
targeting the `dev` branch. Your PR can then be reviewed and discussed.

> Helpful: Run `make` in the project root directory and ensure all tests pass.
> If tests are not passing and you need help resolving the problem, please mention this in your PR.


## Adding new feature layers

Feature [Layers](layersets.html#layers) define the data loaded by PgOSM Flex into
the target Postgres / PostGIS database.



Checklist for adding new feature layers:

* [ ] Create `flex-config/style/<feature>.lua`
* [ ] Create `flex-config/sql/<feature>.sql`
* [ ] Update `flex-config/run.lua`
* [ ] Update `flex-config/run.sql`
* [ ] Update `db/qc/features_not_in_run_all.sql`
* [ ] Add relevant `tests/sql/<feature_queries>.sql`
* [ ] Add relevant `tests/expected/<feature_queries>.out`



## Style guides


### Written content in GitHub


See [GitHub's Markdown documentation](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)
for more on writing with formatting in GitHub.

* Use headers to outline sections when using more than two or three paragraphs.
* Format `code` when using with inline text.  
* Use code blocks for multi-line code examples.



### Commit Messages

Brief, descriptive commit messages are appreciated.  Lengthy commit messages
will likely never be reviewed.  Detailed explanations and discussions are appropriate
in GitHub Pull Request, Issues, and/or discussions.



## Legal Notice

When contributing to this project, you must agree that you have authored 100% of the content, that you have the necessary rights to the content and that the content you contribute may be provided under the project license.




## Attribution

This guide is loosely based on the
[example **contributing.md** site](https://contributing.md/).
