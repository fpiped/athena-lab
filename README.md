# athena-lab

A lab for AWS Athena on a real AWS account: one setup and teardown, and benches that run against it.
Each check reads its result back from Athena, Glue, S3 or Lake Formation rather than trusting an exit
code.

Not an official AWS or dbt Labs project.

| Bench | What it tests |
|---|---|
| [`dbt2/`](dbt2/README.md) | the AWS Athena adapter of dbt 2 and its ADBC driver, assembled from open pull requests |
| [`quirks/`](quirks/README.md) | one rerunnable reproduction per Athena engine quirk, each printing its verdict |

Formerly `fpiped/dbt2-athena-lab`, when it held only the dbt 2 bench.

## Quick start

Requirements: git, the AWS CLI v2, `jq`, Python 3, and an AWS account where you can create Athena work
groups and IAM roles. Each bench lists its own on top of these.

```sh
cp env.example.sh env.sh      # account, region, prefix, bucket, optional sections
setup/setup.sh                # work groups, roles and the rest, named from the prefix
# run a bench
setup/teardown.sh             # removes what setup.sh and the benches created
```

The scripts refuse to run against an account other than `LAB_ACCOUNT_ID`.

## Local files

Keep account settings in the ignored `env.sh` (or another ignored `env.*.sh`).
Private notes, experiments and historical material belong in the ignored `.local/`
directory. Keep reusable scripts and tests in this repository rather than maintaining
a second lab.

With an IAM Identity Center (SSO) profile, export its credentials before a run. Runs on the profile
have stalled for minutes on each call (a three-model dbt compile took 17 minutes, one second with the
same credentials exported), while the AWS CLI kept working; the cause is not known (an expired SSO token
is refreshed normally).

```bash
eval "$(aws configure export-credentials --profile <profile> --format env)"
```

## License

Apache-2.0.
