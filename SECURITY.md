# Security

Every consumer runs this repository's workflows and executables, so a vulnerability here reaches all
of them. Report one privately through GitHub's "Report a vulnerability" on this repository, not in a
public issue. Only the latest `v2` release is supported.

What the repository relies on: third-party actions pinned by commit SHA, zizmor and actionlint in CI,
no secret stored here (callers pass their own, explicitly), and release tags pushed only by the owner.
